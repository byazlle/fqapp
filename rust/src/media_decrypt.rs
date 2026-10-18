//! 桌面端短剧/漫剧流式解密。
//!
//! Android 上由 ExoPlayer + JNI 回调 OkHttp 直接读 CENC 加密 MP4；桌面端没有
//! 这套宿主，于是在 Rust 侧把 C 解密核心（`native/crypto_core`，由 build.rs
//! 编译）串起来：`sp_io` 回调通过 reqwest 按 HTTP Range 回源，`sp_stream_*`
//! 负责解析与 AES-CTR 解密，再以一个支持 seek 的 `AsyncRead` 暴露给 loopback
//! server。播放器（media_kit / libmpv）访问本地解密 URL，和普通 MP4 无异。
//!
//! 解密是按字节 XOR，不改变文件长度，因此解密流总大小 == 加密源大小。

use std::ffi::c_void;
use std::os::raw::c_int;
use std::task::Poll;

use tokio::io::{AsyncRead, AsyncSeek, SeekFrom};
use tokio_util::sync::CancellationToken;

use crate::upstream::http::{build_tls_config, ensure_crypto_provider};

type SpResult = c_int;

#[repr(C)]
struct SpError {
    code: SpResult,
    message: [u8; 192],
}

#[repr(C)]
struct SpIo {
    user: *mut c_void,
    size: unsafe extern "C" fn(*mut c_void) -> i64,
    read_at: unsafe extern "C" fn(*mut c_void, u64, *mut u8, usize) -> isize,
    cancel: unsafe extern "C" fn(*mut c_void),
    close: Option<unsafe extern "C" fn(*mut c_void)>,
}

#[repr(C)]
struct SpStream {
    _opaque: [u8; 0],
}

unsafe extern "C" {
    fn sp_stream_open(io: *const SpIo, key: *const u8, error: *mut SpError) -> *mut SpStream;
    fn sp_stream_read(
        stream: *mut SpStream,
        buffer: *mut u8,
        length: usize,
        error: *mut SpError,
    ) -> isize;
    fn sp_stream_seek(stream: *mut SpStream, position: i64, error: *mut SpError) -> i64;
    fn sp_stream_cancel(stream: *mut SpStream);
    fn sp_stream_close(stream: *mut SpStream);
}

/// 回源 I/O 上下文，地址在整个流生命周期内固定（`sp_stream` 只存裸指针）。
struct IoContext {
    url: String,
    client: reqwest::Client,
    handle: tokio::runtime::Handle,
    size: i64,
    cancel: std::sync::Mutex<Option<CancellationToken>>,
}

struct Inner {
    stream: *mut SpStream,
    io_ctx: *mut IoContext,
}

// sp_stream 由调用方串行化访问（cancel 除外）；我们只通过 spawn_blocking 串行
// 调用，并把裸指针集中在 `Inner` 上。
unsafe impl Send for Inner {}

/// 让 `spawn_blocking` 闭包可以携带裸指针。串行访问由 `DecryptReader`
/// 保证（同一时刻只有一个读取/定位任务）。
///
/// 注意必须用 [SendPtr::into_raw] 取指针：若在闭包里直接写 `p.0`，Rust 2021
/// 的精确捕获会绕过包装、直接捕获内部裸指针（不 Send）。
struct SendPtr<T>(*mut T);
impl<T> SendPtr<T> {
    fn into_raw(self) -> *mut T {
        self.0
    }
}
unsafe impl<T> Send for SendPtr<T> {}

fn err_message(err: &SpError) -> String {
    let end = err.message.iter().position(|&b| b == 0).unwrap_or(0);
    String::from_utf8_lossy(&err.message[..end]).into_owned()
}

unsafe extern "C" fn cb_size(user: *mut c_void) -> i64 {
    let ctx = &*(user as *const IoContext);
    ctx.size
}

unsafe extern "C" fn cb_cancel(user: *mut c_void) {
    let ctx = &*(user as *const IoContext);
    if let Ok(guard) = ctx.cancel.lock() {
        if let Some(token) = guard.as_ref() {
            token.cancel();
        }
    }
}

async fn read_range(
    ctx: &IoContext,
    offset: u64,
    buffer: *mut u8,
    length: usize,
) -> Result<usize, String> {
    let token = CancellationToken::new();
    if let Ok(mut guard) = ctx.cancel.lock() {
        *guard = Some(token.clone());
    }
    let request = async {
        let end = offset + length as u64 - 1;
        let resp = ctx
            .client
            .get(&ctx.url)
            .header(reqwest::header::RANGE, format!("bytes={offset}-{end}"))
            .send()
            .await
            .map_err(|e| e.to_string())?;
        let bytes = resp.bytes().await.map_err(|e| e.to_string())?;
        Ok::<bytes::Bytes, String>(bytes)
    };
    tokio::select! {
        _ = token.cancelled() => Err("cancelled".to_string()),
        result = request => {
            if let Ok(mut guard) = ctx.cancel.lock() {
                *guard = None;
            }
            let bytes = result?;
            let n = bytes.len().min(length);
            unsafe {
                let dst = std::slice::from_raw_parts_mut(buffer, length);
                dst[..n].copy_from_slice(&bytes[..n]);
            }
            Ok(n)
        }
    }
}

unsafe extern "C" fn cb_read_at(
    user: *mut c_void,
    offset: u64,
    buffer: *mut u8,
    length: usize,
) -> isize {
    if length == 0 {
        return 0;
    }
    let ctx = &*(user as *const IoContext);
    // 运行在 spawn_blocking 线程（非 tokio worker），在此 block_on 安全。
    match ctx.handle.block_on(read_range(ctx, offset, buffer, length)) {
        Ok(n) => n as isize,
        Err(_) => -1,
    }
}

fn build_client() -> Result<reqwest::Client, String> {
    ensure_crypto_provider();
    let tls = build_tls_config()?;
    reqwest::Client::builder()
        .tls_backend_preconfigured(tls)
        .build()
        .map_err(|e| format!("build media client: {e}"))
}

async fn probe_size(client: &reqwest::Client, url: &str) -> Result<u64, String> {
    let resp = client
        .get(url)
        .header(reqwest::header::RANGE, "bytes=0-0")
        .send()
        .await
        .map_err(|e| format!("probe size: {e}"))?;
    // 支持 Range 的服务器：206 + Content-Range: bytes 0-0/TOTAL。
    if let Some(value) = resp.headers().get(reqwest::header::CONTENT_RANGE) {
        if let Ok(text) = value.to_str() {
            if let Some(total) = text.rsplit('/').next() {
                if let Ok(size) = total.parse::<u64>() {
                    return Ok(size);
                }
            }
        }
    }
    // 不支持 Range：200 + Content-Length 即总长。
    if let Some(value) = resp.headers().get(reqwest::header::CONTENT_LENGTH) {
        if let Ok(text) = value.to_str() {
            if let Ok(size) = text.parse::<u64>() {
                return Ok(size);
            }
        }
    }
    Err("无法确定媒体总大小".to_string())
}

/// 解密后 MP4 的顺序读取器，支持 seek（供 loopback Range 响应使用）。
pub struct DecryptReader {
    inner: *mut Inner,
    total: u64,
    current: u64,
    read_task: Option<tokio::task::JoinHandle<Result<Vec<u8>, String>>>,
    seek_task: Option<tokio::task::JoinHandle<Result<u64, String>>>,
    seek_target: Option<u64>,
}

unsafe impl Send for DecryptReader {}

impl DecryptReader {
    pub async fn open(url: &str, key: &[u8]) -> Result<DecryptReader, String> {
        if key.len() != 16 {
            return Err("内容密钥必须为 16 字节".to_string());
        }
        let handle = tokio::runtime::Handle::current();
        let client = build_client()?;
        let total = probe_size(&client, url).await?;

        let io_ctx = Box::new(IoContext {
            url: url.to_string(),
            client,
            handle: handle.clone(),
            size: total as i64,
            cancel: std::sync::Mutex::new(None),
        });
        let io_ctx = SendPtr(Box::into_raw(io_ctx));
        let mut key_buf = [0u8; 16];
        key_buf.copy_from_slice(key);

        let open_result = tokio::task::spawn_blocking(move || unsafe {
            let io_ctx = io_ctx.into_raw();
            let io = SpIo {
                user: io_ctx as *mut c_void,
                size: cb_size,
                read_at: cb_read_at,
                cancel: cb_cancel,
                close: None,
            };
            let mut err: SpError = std::mem::zeroed();
            let stream = sp_stream_open(&io, key_buf.as_ptr(), &mut err);
            if stream.is_null() {
                drop(Box::from_raw(io_ctx));
                return Err(err_message(&err));
            }
            let inner = Box::new(Inner { stream, io_ctx });
            Ok(SendPtr(Box::into_raw(inner)))
        })
        .await
        .map_err(|e| format!("open task: {e}"))?;

        let inner = open_result?.0;
        Ok(DecryptReader {
            inner,
            total,
            current: 0,
            read_task: None,
            seek_task: None,
            seek_target: None,
        })
    }

    pub fn total_size(&self) -> u64 {
        self.total
    }
}

impl AsyncRead for DecryptReader {
    fn poll_read(
        self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &mut tokio::io::ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        use futures::FutureExt;
        let me = self.get_mut();
        if me.read_task.is_none() {
            let cap = buf.remaining();
            if cap == 0 {
                return Poll::Ready(Ok(()));
            }
            let inner = SendPtr(me.inner);
            me.read_task = Some(tokio::task::spawn_blocking(move || unsafe {
                let inner = &*inner.into_raw();
                let mut tmp = vec![0u8; cap];
                let mut err: SpError = std::mem::zeroed();
                let n = sp_stream_read(inner.stream, tmp.as_mut_ptr(), cap, &mut err);
                if n < 0 {
                    return Err(err_message(&err));
                }
                tmp.truncate(n as usize);
                Ok(tmp)
            }));
        }
        match me.read_task.as_mut().unwrap().poll_unpin(cx) {
            Poll::Ready(join) => {
                me.read_task = None;
                match join {
                    Ok(Ok(data)) => {
                        let n = data.len();
                        buf.put_slice(&data);
                        me.current += n as u64;
                        Poll::Ready(Ok(()))
                    }
                    Ok(Err(e)) => Poll::Ready(Err(std::io::Error::other(e))),
                    Err(e) => Poll::Ready(Err(std::io::Error::other(e.to_string()))),
                }
            }
            Poll::Pending => Poll::Pending,
        }
    }
}

impl AsyncSeek for DecryptReader {
    fn start_seek(self: std::pin::Pin<&mut Self>, position: SeekFrom) -> std::io::Result<()> {
        let me = self.get_mut();
        let absolute = match position {
            SeekFrom::Start(n) => n,
            SeekFrom::Current(n) => (me.current as i64 + n).max(0) as u64,
            SeekFrom::End(n) => (me.total as i64 + n).max(0) as u64,
        };
        me.seek_target = Some(absolute.min(me.total));
        Ok(())
    }

    fn poll_complete(
        self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> Poll<std::io::Result<u64>> {
        use futures::FutureExt;
        let me = self.get_mut();
        if me.seek_task.is_none() {
            let Some(target) = me.seek_target.take() else {
                return Poll::Ready(Ok(me.current));
            };
            let inner = SendPtr(me.inner);
            me.seek_task = Some(tokio::task::spawn_blocking(move || unsafe {
                let inner = &*inner.into_raw();
                let mut err: SpError = std::mem::zeroed();
                let r = sp_stream_seek(inner.stream, target as i64, &mut err);
                if r < 0 {
                    Err(err_message(&err))
                } else {
                    Ok(r as u64)
                }
            }));
        }
        match me.seek_task.as_mut().unwrap().poll_unpin(cx) {
            Poll::Ready(join) => {
                me.seek_task = None;
                match join {
                    Ok(Ok(pos)) => {
                        me.current = pos;
                        Poll::Ready(Ok(pos))
                    }
                    Ok(Err(e)) => Poll::Ready(Err(std::io::Error::other(e))),
                    Err(e) => Poll::Ready(Err(std::io::Error::other(e.to_string()))),
                }
            }
            Poll::Pending => Poll::Pending,
        }
    }
}

impl Drop for DecryptReader {
    fn drop(&mut self) {
        let inner = SendPtr(self.inner);
        let read_task = self.read_task.take();
        let seek_task = self.seek_task.take();

        // 清理必须串行：先 cancel、等待进行中的读取/定位，再释放，避免对正在
        // 回源的 sp_stream 做 use-after-free。
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            let cleanup = move || {
                let handle = tokio::runtime::Handle::current();
                unsafe {
                    let inner = inner.into_raw();
                    let inner_ref = &*inner;
                    sp_stream_cancel(inner_ref.stream);
                    if let Some(mut task) = seek_task {
                        let _ = handle.block_on(&mut task);
                    }
                    if let Some(mut task) = read_task {
                        let _ = handle.block_on(&mut task);
                    }
                    let inner = Box::from_raw(inner);
                    sp_stream_close(inner.stream);
                    drop(Box::from_raw(inner.io_ctx));
                }
            };
            // 明确 drop：tokio 的 JoinHandle 被丢弃只是脱离任务（不取消），
            // 这里本就是「忘了你」的关闭动作；写成 `let _ =` 会被
            // clippy::let_underscore_future 拦下。
            drop(handle.spawn_blocking(cleanup));
        } else {
            // 无 runtime 时无法等待异步任务，尽力同步关闭。
            unsafe {
                let inner = inner.into_raw();
                let inner_ref = &*inner;
                sp_stream_cancel(inner_ref.stream);
                let inner = Box::from_raw(inner);
                sp_stream_close(inner.stream);
                drop(Box::from_raw(inner.io_ctx));
            }
        }
    }
}
