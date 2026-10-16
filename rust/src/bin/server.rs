//! fqapp 独立服务器版（桌面一键端）。
//!
//! 把内置 Web UI、配置、过滤器与 C 解密库（由 build.rs 编译进同一二进制）
//! 打包为单文件。运行时在 exe 旁建立 `fqapp_runtime/`，释放资源，启动
//! loopback 服务（随机端口），自动打开浏览器。短剧/漫剧走 `/media/play`
//! 解密流，漫画/小说走原 Rust 核心链路。
//!
//! 交叉编译：
//!   cargo build --release --bin fqapp-server --target x86_64-pc-windows-gnu

use std::sync::Arc;

use fqapi_core::config::Config;
use fqapi_core::device::DevicePool;
use fqapi_core::endpoints::{Ctx, Server};
use fqapi_core::filter::FilterManager;
use fqapi_core::server::serve;
use fqapi_core::sign::Manager;
use fqapi_core::upstream::UpstreamClient;

/// (相对 runtime 目录的路径, 内嵌字节)。
const FILES: &[(&str, &[u8])] = &[
    ("config.json", include_bytes!("../../../assets/config/config.json")),
    ("filter.json", include_bytes!("../../../assets/config/filter.json")),
    ("web/index.html", include_bytes!("../../../assets/web/index.html")),
    ("web/comic.html", include_bytes!("../../../assets/web/comic.html")),
    ("web/detail.html", include_bytes!("../../../assets/web/detail.html")),
    ("web/listen.html", include_bytes!("../../../assets/web/listen.html")),
    ("web/read.html", include_bytes!("../../../assets/web/read.html")),
    ("web/video.html", include_bytes!("../../../assets/web/video.html")),
    ("web/favicon.png", include_bytes!("../../../assets/web/favicon.png")),
    (
        "web/assets/css/all.min.css",
        include_bytes!("../../../assets/web/assets/css/all.min.css"),
    ),
    (
        "web/assets/storage.js",
        include_bytes!("../../../assets/web/assets/storage.js"),
    ),
    (
        "web/assets/webfonts/fa-solid-900.woff2",
        include_bytes!("../../../assets/web/assets/webfonts/fa-solid-900.woff2"),
    ),
];

fn release_assets(runtime: &std::path::Path) -> Result<(), String> {
    for (rel, bytes) in FILES {
        let path = runtime.join(rel);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        std::fs::write(&path, bytes).map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn open_browser(url: &str) {
    #[cfg(target_os = "windows")]
    {
        let _ = std::process::Command::new("cmd")
            .args(["/c", "start", "", url])
            .spawn();
    }
    #[cfg(target_os = "linux")]
    {
        let _ = std::process::Command::new("xdg-open").arg(url).spawn();
    }
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("open").arg(url).spawn();
    }
}

struct SimpleLogger;
impl log::Log for SimpleLogger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= log::Level::Warn
    }
    fn log(&self, record: &log::Record) {
        if self.enabled(record.metadata()) {
            eprintln!("[{}] {}", record.level(), record.args());
        }
    }
    fn flush(&self) {}
}
static LOGGER: SimpleLogger = SimpleLogger;
fn init_logger() {
    if log::set_logger(&LOGGER).is_ok() {
        log::set_max_level(log::LevelFilter::Warn);
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    init_logger();
    let exe = std::env::current_exe()?;
    let base = exe.parent().unwrap().to_path_buf();
    let runtime = base.join("fqapp_runtime");
    std::fs::create_dir_all(&runtime)?;
    release_assets(&runtime)?;

    let config_path = runtime.join("config.json");
    let pool_path = runtime.join("device_pool.json");
    let filter_path = runtime.join("filter.json");
    let web_dir = runtime.join("web");
    let src_dir = runtime.join("src");
    std::fs::create_dir_all(&src_dir)?;

    let cfg = Arc::new(Config::load(&config_path.to_string_lossy())?);
    let pool = DevicePool::new(&pool_path).await?;
    let signer = Manager::new();
    let up = Arc::new(UpstreamClient::new(pool.clone(), signer)?);
    let filters = Arc::new(FilterManager::load_with_base(
        &filter_path.to_string_lossy(),
        &runtime.to_string_lossy(),
    )?);

    let ctx = Arc::new(Ctx {
        up,
        pool,
        cfg: cfg.clone(),
        src_dir: src_dir.to_string_lossy().into_owned(),
        web_dir: web_dir.to_string_lossy().into_owned(),
        filters,
    });
    let server = Arc::new(Server::new(ctx));

    // 随机端口，避免与本机 8080 冲突。
    let handle = serve(server, 0).await.map_err(|e| {
        eprintln!("启动失败: {e}");
        e
    })?;
    // 首次入口必须带会话令牌：服务器会种下 cookie 再跳转到 /，之后浏览器
    // 访问同源页面即可通过校验。
    let url = format!(
        "http://127.0.0.1:{}/_session/{}/",
        handle.port, handle.token
    );
    println!("番茄 PC 服务器版已启动：http://127.0.0.1:{}/", handle.port);
    println!("入口地址：{url}");
    println!("关闭本窗口即停止服务。若浏览器未自动打开，请手动复制上面的地址。");
    open_browser(&url);

    // 保持运行，直到窗口关闭或 Ctrl+C。
    tokio::signal::ctrl_c().await.ok();
    Ok(())
}
