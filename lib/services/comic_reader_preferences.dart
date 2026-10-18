import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 漫画翻页模式的每屏页数偏好。
///
/// 0 = 自动（跟随窗口宽度），1..4 = 固定页数。宽屏桌面窗口可以并排浏览
/// 2/3/4 页；窄窗口（手机）无论偏好如何都收敛为单页，保证每页都有可读的
/// 尺寸。偏好与小说阅读的 `reader_page_columns` 相互独立——漫画页是整幅
/// 图像，并排时靠 `BoxFit.contain` 适配，和文字分页的几何不同。
@immutable
class ComicReaderPreferences {
  static Future<void>? _writes;
  static const _spreadPagesKey = 'comic_spread_pages';

  /// 单列最小宽度：低于它就不再增加并排页数。
  static const double _minColumnWidth = 340;

  final int spreadPages;

  const ComicReaderPreferences({this.spreadPages = 0});

  ComicReaderPreferences copyWith({int? spreadPages}) =>
      ComicReaderPreferences(spreadPages: spreadPages ?? this.spreadPages)
          .normalized();

  ComicReaderPreferences normalized() =>
      ComicReaderPreferences(spreadPages: spreadPages.clamp(0, 4));

  static Future<ComicReaderPreferences> load() async {
    await _writes;
    final preferences = await SharedPreferences.getInstance();
    return ComicReaderPreferences(
      spreadPages: (preferences.get(_spreadPagesKey) as int? ?? 0).clamp(0, 4),
    );
  }

  Future<void> save() {
    final snapshot = normalized();
    final previous = _writes ?? Future<void>.value();
    final write = previous.then((_) => snapshot._write());
    final settled = write.catchError((Object _) {});
    _writes = settled;
    return write.whenComplete(() {
      if (identical(_writes, settled)) _writes = null;
    });
  }

  Future<void> _write() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_spreadPagesKey, normalized().spreadPages);
  }

  /// 窗口宽度 [width] 下实际并排的页数。
  ///
  /// 自动档按窗口宽度分档（<760 单页，<1320 双页，<1880 三页，更宽四页），
  /// 同时受单列最小宽度约束；固定档同样受宽度约束收敛，例如 1000 像素的
  /// 窗口即使选择四页也只排两页。
  static int spreadForWidth(double width, {int preferred = 0}) {
    if (!width.isFinite || width <= 0) return 1;
    final maxByWidth = math
        .max(1, math.min(4, width ~/ _minColumnWidth))
        .toInt();
    if (preferred <= 0) {
      if (width < 760) return 1;
      if (width < 1320) return 2;
      if (width < 1880) return 3;
      return maxByWidth;
    }
    return math.min(preferred, maxByWidth);
  }
}
