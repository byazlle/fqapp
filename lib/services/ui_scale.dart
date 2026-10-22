import 'package:flutter/foundation.dart';

/// 应用内界面缩放：整体 UI（文字 + 布局）按比例缩放，类似浏览器缩放。
/// 1.0 为默认；数值越大界面越大、同一窗口能容纳的内容越少。
///
/// 与系统 DPI 缩放独立：系统 DPI 由 Windows 负责，这里只解决「同一个窗口
/// 下还想再放大/缩小一点」的需求（高分屏远看、或想一屏看更多内容）。
const String uiScaleKey = 'uiScale';

/// 可选档位。0.9 适合想一屏看到更多内容，1.25 适合远距离观看。
const List<double> uiScaleOptions = [0.9, 1.0, 1.1, 1.25];

final ValueNotifier<double> uiScaleNotifier = ValueNotifier<double>(1.0);

double clampUiScale(double value) {
  if (!value.isFinite) return 1.0;
  return value.clamp(0.8, 1.4);
}

String uiScaleLabel(double value) => '${(value * 100).round()}%';
