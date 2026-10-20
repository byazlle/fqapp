import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 听书相关配置与持久化偏好设置。
class AudioPreferences {
  AudioPreferences._();

  static final AudioPreferences instance = AudioPreferences._();

  static const _backgroundPlaybackKey = 'audio_background_playback_enabled';

  /// 是否允许后台播放（默认 true）。桌面端没有锁屏与通知栏，这里的「后台」
  /// 指窗口失焦或被最小化；Android 端由前台保活服务常驻通知栏与提供控制卡片。
  /// 开启：切到其他窗口或最小化时继续播放；关闭：切走即自动暂停并移除前台通知。
  final ValueNotifier<bool> backgroundPlayback = ValueNotifier<bool>(true);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      backgroundPlayback.value = sp.getBool(_backgroundPlaybackKey) ?? true;
    } catch (_) {
      // 异常时退回默认开启
    }
  }

  /// 重置测试状态，让下一次 [load] 重新读取 SharedPreferences。
  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    backgroundPlayback.value = true;
  }

  Future<void> setBackgroundPlayback(bool value) async {
    backgroundPlayback.value = value;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_backgroundPlaybackKey, value);
    } catch (_) {
      // 忽略持久化失败
    }
  }
}
