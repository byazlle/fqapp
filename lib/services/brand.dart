import 'package:flutter/material.dart';

/// 流光 (Liuguang) 的品牌常量：名称、色板、圆角。
///
/// 视觉语言定为「极光玻璃（aurora glass）」：深紫到青的液态渐变作底，
/// 半透明面板叠在上面，靠模糊 + 双道高光边 + 柔光晕制造层次。
/// 所有页面只从这里取色，不再各写 `Color(0xFF...)`。
class Brand {
  const Brand._();

  /// 中文名：界面上一律用它。
  static const String name = '流光';

  /// 拉丁名：安装包、版本信息、图标署名用。
  static const String latin = 'Liuguang';

  static const String tagline = '好故事，不止一种';
  static const String discipline = '小说 · 短剧 · 漫剧 · 漫画 · 听书';

  /// 主色：电光紫。
  static const Color primary = Color(0xFF7C5CFF);
  static const Color primaryDeep = Color(0xFF5B3DE8);
  static const Color primarySoft = Color(0xFF9B85FF);

  /// 辅助色：极光青，渐变收尾与次要强调。
  static const Color secondary = Color(0xFF22D3EE);

  /// 高光色：品红，只做氛围。
  static const Color highlight = Color(0xFFF472B6);

  /// 品牌渐变：紫 → 青。
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, Color(0xFF6D6BFF), secondary],
    stops: [0.0, 0.55, 1.0],
  );

  /// 液态三色，用于大面积底纹。
  static const List<Color> aurora = [Color(0xFF4C1D95), primary, secondary];

  static const Color lightCanvas = Color(0xFFF6F7FC);
  static const Color darkCanvas = Color(0xFF0A0C14);
}

/// 圆角阶梯：控件 14、卡片 20、面板 26、弹层 30。
class BrandRadii {
  const BrandRadii._();
  static const double control = 14;
  static const double card = 20;
  static const double panel = 26;
  static const double sheet = 30;
}
