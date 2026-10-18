import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show BoxFit;
import 'package:flutter/widgets.dart' show SizedBox, ValueKey, Widget;
import 'package:media_kit/media_kit.dart' show Media, MediaKit, Player;
import 'package:media_kit_video/media_kit_video.dart'
    show Video, VideoController;

import 'backend_service.dart';
import 'native_player.dart';

/// 平台自适应的播放器工厂。
///
/// Android 用 [NativePlayer]（ExoPlayer 原生宿主，播放器内解密）；
/// Windows / Linux / macOS 用 [DesktopMediaPlayer]（media_kit + loopback
/// 解密流）。测试与桌面调试都只应依赖这一个入口，避免平台分支散落。
NativePlayer createPlayerForCurrentPlatform() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return DesktopMediaPlayer();
  }
  return NativePlayer();
}

/// 桌面端短剧/听书播放器：media_kit（libmpv）播放 Rust 核心的解密流。
///
/// 背景：Android 的 ExoPlayer 可以直接播放加密流（创建时把
/// `cdnUrl + keyHex` 交给原生层，由播放器解密）。桌面没有这个原生宿主，
/// 但 Rust 核心的 loopback 适配器早就提供了等价端点：
///
///   `GET /media/play?url=<CDN>&key=<keyHex>`
///
/// 它按 HTTP Range 回源加密 MP4，用同一把 key 边下边解密，以 `video/mp4`
/// 流出（内置 Web UI 的 `video.html` 一直在用这条链路）。桌面播放器只需
/// 把这个 URL 交给 libmpv。
///
/// 本类继承 [NativePlayer] 并覆写全部公开面，因此播放页、控制层
/// （video_player_chrome）、听书页与 audio_playback_controller 都无需
/// 区分平台：构造走 [createPlayerForCurrentPlatform]，视频画面由播放页
/// 的桌面分支挂载 [buildVideoSurface]。
class DesktopMediaPlayer extends NativePlayer {
  static const _createTimeout = Duration(seconds: 25);

  /// 桌面播放器实例注册表。基类的 `_instances` 只在原生 `create` 成功后
  /// 登记，桌面播放器覆写了 create、永远走不到那条路，因此
  /// [NativePlayer.pauseOthers] 看不见桌面实例——音视频互斥（听书音频与
  /// 短剧视频不得同时出声）在本类内自查，语义与基类一致：起播前暂停
  /// 其他仍处于 playWhenReady 的桌面播放器。
  static final Map<int, DesktopMediaPlayer> _desktopInstances = {};
  static int _nextInstanceId = 0;

  Player? _mkPlayer;
  VideoController? _mkController;
  final List<StreamSubscription<dynamic>> _mkSubscriptions = [];
  final Completer<void> _firstFrameGate = Completer<void>();
  bool _firstFrameSeen = false;
  bool _disposed = false;
  int? _instanceId;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _playWhenReady = false;
  bool _completed = false;
  bool _buffering = false;
  int _width = 0;
  int _height = 0;
  Object? _error;

  final _positionEvents = StreamController<Duration>.broadcast();
  final _durationEvents = StreamController<Duration>.broadcast();
  final _playingEvents = StreamController<bool>.broadcast();
  final _playWhenReadyEvents = StreamController<bool>.broadcast();
  final _completedEvents = StreamController<bool>.broadcast();
  final _bufferingEvents = StreamController<bool>.broadcast();
  final _firstFrameEvents = StreamController<bool>.broadcast();
  final _videoSizeEvents = StreamController<Size>.broadcast();
  final _textureIdEvents = StreamController<int>.broadcast();
  final _errorEvents = StreamController<Object>.broadcast();

  // ---- 覆写 NativePlayer 的公开面 ----

  /// 桌面渲染不经 Texture 而是 [buildVideoSurface]（media_kit 的
  /// [Video] widget），因此这里恒为 null；播放页桌面分支不读它。
  @override
  int? get textureId => null;

  @override
  bool get isCreated => _mkPlayer != null && !_disposed;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  bool get playing => _playing;

  @override
  bool get playWhenReady => _playWhenReady;

  @override
  bool get completed => _completed;

  @override
  bool get buffering => _buffering;

  @override
  bool get firstFrameRendered => _firstFrameSeen;

  @override
  int get videoWidth => _width;

  @override
  int get videoHeight => _height;

  /// libmpv 自己应用画面旋转，无需宿主再转一次。
  @override
  int get videoRotationCorrection => 0;

  @override
  Object? get lastError => _error;

  @override
  Stream<Duration> get positionStream => _positionEvents.stream;

  @override
  Stream<Duration> get durationStream => _durationEvents.stream;

  @override
  Stream<bool> get playingStream => _playingEvents.stream;

  @override
  Stream<bool> get playWhenReadyStream => _playWhenReadyEvents.stream;

  @override
  Stream<bool> get completedStream => _completedEvents.stream;

  @override
  Stream<bool> get bufferingStream => _bufferingEvents.stream;

  @override
  Stream<bool> get firstFrameStream => _firstFrameEvents.stream;

  @override
  Stream<Size> get videoSizeStream => _videoSizeEvents.stream;

  @override
  Stream<int> get textureIdStream => _textureIdEvents.stream;

  @override
  Stream<Object> get errorStream => _errorEvents.stream;

  /// 视频画面。由播放页 `_videoArea` 的桌面分支挂载；未创建时给空白，
  /// 避免在创建窗口期渲染一个没有 controller 的 [Video]。
  Widget buildVideoSurface() {
    final controller = _mkController;
    if (controller == null) return const SizedBox.shrink();
    return Video(
      key: const ValueKey('desktop-player-video'),
      controller: controller,
      // 控制层用应用自带的 video_player_chrome，不叠 libmpv 的默认控件。
      controls: null,
      fit: BoxFit.contain,
      // 息屏与前后台暂停由应用chrome统一管理（与 Android 行为一致），
      // 不让 media_kit 内置逻辑二次干预。
      wakelock: false,
      pauseUponEnteringBackgroundMode: false,
      resumeUponEnteringForegroundMode: false,
    );
  }

  @override
  Future<int> create(String cdnUrl, String keyHex) async {
    if (_disposed) {
      return Future<int>.error(StateError('DesktopMediaPlayer is disposed'));
    }
    try {
      // media_kit 懒初始化兜底：main() 已在启动时调用过一次（同 zone 纪律见
      // 那里的注释），这里是幂等重入；没有它时任何未经 main() 的入口
      // （听书页直推、调试热路径）都会踩到
      // 「ensureInitialized must be called」这种指错方向的报错。
      MediaKit.ensureInitialized();
      final mediaUrl = _mediaPlayUrl(cdnUrl, keyHex);
      final player = Player();
      final controller = VideoController(player);
      _mkPlayer = player;
      _mkController = controller;
      _wire(player, controller);

      // 与原生语义一致：先准备（不出声、停在首帧），起播由页面驱动。
      // open 本身不回报成败：失败经 error 流进入 [_raiseError]，
      // 打不开则由下面的首帧闸门超时收口。
      await player.open(Media(mediaUrl), play: false);
      // 首帧或致命错误二选一，超时按加载失败处理。
      await _firstFrameGate.future.timeout(_createTimeout);
      _instanceId = ++_nextInstanceId;
      _desktopInstances[_instanceId!] = this;
      // 桌面渲染不经 Texture，这个 id 只是占位（见 [_videoArea] 桌面分支）。
      return 1;
    } catch (error) {
      _raiseError(error);
      await _release();
      rethrow;
    }
  }

  @override
  Future<void> play() => _setPlayWhenReady(true);

  @override
  Future<void> pause() => _setPlayWhenReady(false);

  Future<void> _setPlayWhenReady(bool value) async {
    if (_disposed) return;
    final player = _mkPlayer;
    if (player == null) return;
    _playWhenReady = value;
    if (!_playWhenReadyEvents.isClosed) _playWhenReadyEvents.add(value);
    try {
      if (value) {
        // 与基类语义一致：起播前先过音视频协调闸门
        // （audio_playback_scope 注册的 beforePlay），再暂停其他仍想播的
        // 桌面播放器——桌面没有原生 create，pauseOthers 的基类注册表是
        // 空的，必须在本类内自查（见 [_desktopInstances]）。
        await NativePlayer.beforePlay?.call(this);
        for (final other in _desktopInstances.values.toList(growable: false)) {
          if (!identical(other, this) && other._playWhenReady) {
            await other.pause();
          }
        }
        await player.play();
      } else {
        await player.pause();
      }
    } catch (_) {
      // 平台确认失败不改变播放意图（与原生实现一致）。
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    final player = _mkPlayer;
    if (player == null) return;
    try {
      await player.seek(position);
    } catch (_) {
      // seek 失败时保持当前进度，不撒谎。
      return;
    }
    // 与原生一致：立即采用已确认的进度并清除完成态，让 UI 先动起来。
    _position = position;
    _completed = false;
    if (!_positionEvents.isClosed) _positionEvents.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    final player = _mkPlayer;
    if (player == null || _disposed) return;
    try {
      // NativePlayer 的音量是 0..1；libmpv 是 0..100。
      await player.setVolume(volume.clamp(0.0, 1.0) * 100.0);
    } catch (_) {
      // 音量只是表现层，失败不拖垮播放。
    }
  }

  @override
  Future<void> setRate(double rate) async {
    final player = _mkPlayer;
    if (player == null || _disposed) return;
    try {
      await player.setRate(rate);
    } catch (_) {
      // 倍速失败保持当前速率。
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _release();
    await _closeEventControllers();
    // 基类的流控制器从未被喂过数据，但关掉可以避免 StreamController 泄漏。
    await super.dispose();
  }

  // ---- 内部实现 ----

  Future<void> _closeEventControllers() async {
    await Future.wait(<Future<void>>[
      _positionEvents.close(),
      _durationEvents.close(),
      _playingEvents.close(),
      _playWhenReadyEvents.close(),
      _completedEvents.close(),
      _bufferingEvents.close(),
      _firstFrameEvents.close(),
      _videoSizeEvents.close(),
      _textureIdEvents.close(),
      _errorEvents.close(),
    ]);
  }

  Future<void> _release() async {
    final id = _instanceId;
    if (id != null) {
      _desktopInstances.remove(id);
      _instanceId = null;
    }
    for (final subscription in _mkSubscriptions) {
      await subscription.cancel();
    }
    _mkSubscriptions.clear();
    final player = _mkPlayer;
    _mkPlayer = null;
    _mkController = null;
    if (player != null) {
      try {
        await player.dispose();
      } catch (_) {
        // 释放是尽力而为：引擎关闭时原生侧可能已经没了。
      }
    }
  }

  void _wire(Player player, VideoController controller) {
    _mkSubscriptions.add(
      player.stream.position.listen((value) {
        _position = value;
        if (!_positionEvents.isClosed) _positionEvents.add(value);
      }),
    );
    _mkSubscriptions.add(
      player.stream.duration.listen((value) {
        _duration = value;
        if (!_durationEvents.isClosed) _durationEvents.add(value);
      }),
    );
    _mkSubscriptions.add(
      player.stream.playing.listen((value) {
        _playing = value;
        if (!_playingEvents.isClosed) _playingEvents.add(value);
      }),
    );
    _mkSubscriptions.add(
      player.stream.completed.listen((value) {
        _completed = value;
        if (!_completedEvents.isClosed) _completedEvents.add(value);
      }),
    );
    _mkSubscriptions.add(
      player.stream.buffering.listen((value) {
        _buffering = value;
        if (!_bufferingEvents.isClosed) _bufferingEvents.add(value);
      }),
    );
    _mkSubscriptions.add(
      player.stream.width.listen((value) {
        if (value == null || value <= 0) return;
        _width = value;
        _emitVideoSize();
      }),
    );
    _mkSubscriptions.add(
      player.stream.height.listen((value) {
        if (value == null || value <= 0) return;
        _height = value;
        _emitVideoSize();
      }),
    );
    _mkSubscriptions.add(
      player.stream.error.listen((message) {
        _raiseError(
          NativePlaybackException(
            message.isEmpty ? '桌面播放器错误' : message,
          ),
        );
      }),
    );
    // 首帧信号双保险：渲染回调 + 视频参数就绪（任一先到都收起加载态）。
    unawaited(
      controller.waitUntilFirstFrameRendered
          .then((_) => _markFirstFrame())
          .catchError((Object _) {
        // 加载失败时该 future 不会 reject；错误经 error 流上报。
      }),
    );
  }

  void _emitVideoSize() {
    if (_width <= 0 || _height <= 0) return;
    if (!_videoSizeEvents.isClosed) {
      _videoSizeEvents.add(Size(_width.toDouble(), _height.toDouble()));
    }
    _markFirstFrame();
  }

  void _markFirstFrame() {
    if (_firstFrameSeen || _disposed) return;
    _firstFrameSeen = true;
    if (!_firstFrameGate.isCompleted) _firstFrameGate.complete();
    if (!_firstFrameEvents.isClosed) _firstFrameEvents.add(true);
    if (!_textureIdEvents.isClosed) _textureIdEvents.add(0);
  }

  void _raiseError(Object error) {
    if (_disposed) return;
    _error = error;
    if (!_errorEvents.isClosed) _errorEvents.add(error);
    if (!_firstFrameGate.isCompleted) _firstFrameGate.completeError(error);
  }

  /// 拼出 loopback 解密流地址。能力令牌走 `/_session/<cap>/` 路径前缀
  /// （与 Web UI、封面图同一套约定），CDN 地址整体编码，避免它的查询
  /// 参数被误认为是本端的参数。
  String _mediaPlayUrl(String cdnUrl, String keyHex) {
    if (cdnUrl.startsWith('file://')) {
      // `/media/play` 只能按 HTTP Range 回源；桌面暂不放行本地加密文件，
      // 由调用方（播放页）回退在线链路。
      throw NativePlaybackException('桌面版暂不支持离线缓存播放，请联网播放');
    }
    final base = BackendService.instance.webUiEntryUrl;
    final query =
        'url=${Uri.encodeComponent(cdnUrl)}&key=${Uri.encodeComponent(keyHex)}';
    return '${base}media/play?$query';
  }
}
