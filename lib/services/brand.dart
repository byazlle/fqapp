import 'package:flutter/material.dart';

/// 番茄端碗 (FanqieDuanwan) 的品牌常量：名称、色板、圆角。
///
/// 名字取自内容来源——番茄小说与番茄视频——所以视觉也跟着换了主语：
/// 番茄红到琥珀橙的暖色液态底，半透明面板叠在上面，靠模糊 + 双道高光边 +
/// 柔光晕制造层次。所有页面只从这里取色，不再各写 `Color(0xFF...)`。
class Brand {
  const Brand._();

  /// 中文名：界面上一律用它。
  static const String name = '番茄端碗';

  /// 拉丁名：安装包、版本信息、图标署名用。
  static const String latin = 'FanqieDuanwan';

  static const String tagline = '番茄的剧，端在碗里';
  static const String discipline = '小说 · 短剧 · 漫剧 · 漫画 · 听书';

  /// 主色：番茄红。界面强调、选中态、进度条都用它。
  static const Color primary = Color(0xFFE8342A);
  static const Color primaryDeep = Color(0xFFB3121C);
  static const Color primarySoft = Color(0xFFFF7A5C);

  /// 辅助色：熟透的橙，渐变收尾与次要强调。
  static const Color secondary = Color(0xFFFF9F1C);

  /// 高光色：琥珀，只做氛围。
  static const Color highlight = Color(0xFFFFC94B);

  /// 品牌渐变：番茄红 → 橙。
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, Color(0xFFFF6B3D), secondary],
    stops: [0.0, 0.55, 1.0],
  );

  /// 液态三色，用于大面积底纹。
  static const List<Color> aurora = [Color(0xFF7A0B14), primary, secondary];

  /// 暖白与暖黑：纯白/纯黑会让番茄红显脏。
  static const Color lightCanvas = Color(0xFFFDF7F2);
  static const Color darkCanvas = Color(0xFF150C0B);
}

/// 圆角阶梯：控件 14、卡片 20、面板 26、弹层 30。
class BrandRadii {
  const BrandRadii._();
  static const double control = 14;
  static const double card = 20;
  static const double panel = 26;
  static const double sheet = 30;
}
