import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../services/brand.dart';

/// 流光的品牌视觉基元：全屏液态底、玻璃面板、品牌标识。
///
/// 墨水屏模式（`eink`）下这些效果全部退化为纯白底 + 黑描边：毛玻璃在
/// 墨水屏上会被量化成一片灰，残影明显。

/// 全屏液态底：基础渐变 + 三团极光晕。
///
/// 只画一次渐变，不用 BackdropFilter，滚动时不会有额外采样开销。
class BrandBackdrop extends StatelessWidget {
  const BrandBackdrop({super.key, required this.child, this.eink = false});

  final Widget child;
  final bool eink;

  @override
  Widget build(BuildContext context) {
    if (eink) {
      return ColoredBox(color: Colors.white, child: child);
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? Brand.darkCanvas : Brand.lightCanvas;
    // 深色模式给更多色彩，浅色模式压到很淡，保证正文对比度。
    final violetAlpha = dark ? 84 : 34;
    final cyanAlpha = dark ? 52 : 26;
    final pinkAlpha = dark ? 44 : 20;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF0A0C14), const Color(0xFF111534), const Color(0xFF0A1018)]
              : [const Color(0xFFF7F8FE), const Color(0xFFF2F1FE), const Color(0xFFF4FBFD)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -180,
            right: -160,
            child: _Blob(
              size: 520,
              color: Brand.primary.withValues(alpha: violetAlpha / 255),
            ),
          ),
          Positioned(
            bottom: -220,
            left: -180,
            child: _Blob(
              size: 560,
              color: Brand.secondary.withValues(alpha: cyanAlpha / 255),
            ),
          ),
          Positioned(
            top: 120,
            left: -140,
            child: _Blob(
              size: 360,
              color: Brand.highlight.withValues(alpha: pinkAlpha / 255),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

/// 玻璃面板：模糊背景 + 半透明染色 + 双道高光边 + 柔和外阴影。
///
/// [blur] 为 0 时不挂 BackdropFilter（列表里大量小卡片用实色更省）。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = BrandRadii.panel,
    this.blur = 22,
    this.padding,
    this.eink = false,
    this.opacity,
    this.tinted = false,
    this.border = true,
    this.shadow = true,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final bool eink;

  /// 面板底色不透明度；默认浅色 0.72 / 深色 0.55。
  final double? opacity;

  /// 是否用品牌渐变做极淡的染色（主面板用，列表卡片不用）。
  final bool tinted;
  final bool border;
  final bool shadow;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);

    if (eink) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius,
          border: Border.all(color: Colors.black, width: 0.8),
        ),
        clipBehavior: clipBehavior,
        child: child,
      );
    }

    final base = dark ? const Color(0xFF12141F) : Colors.white;
    final tint = (opacity ?? (dark ? 0.58 : 0.74)).clamp(0.0, 1.0);
    final fill = Color.alphaBlend(base.withValues(alpha: tint), Colors.transparent);

    Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: fill,
        gradient: tinted
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    Brand.primary.withValues(alpha: dark ? 0.20 : 0.10),
                    fill,
                  ),
                  fill,
                  Color.alphaBlend(
                    Brand.secondary.withValues(alpha: dark ? 0.14 : 0.07),
                    fill,
                  ),
                ],
              )
            : null,
        border: border
            ? Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.85),
                width: 0.9,
              )
            : null,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    if (blur > 0) {
      panel = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: panel,
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.45 : 0.07),
                  blurRadius: 30,
                  spreadRadius: -6,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: Brand.primary.withValues(alpha: dark ? 0.16 : 0.06),
                  blurRadius: 18,
                  spreadRadius: -8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(borderRadius: borderRadius, clipBehavior: clipBehavior, child: panel),
    );
  }
}

/// 品牌标识：图标 + 可选文字。图标走 `assets/images/app_logo.webp`。
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 32,
    this.radius = 9,
    this.eink = false,
    this.glow = true,
  });

  final double size;
  final double radius;
  final bool eink;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/images/app_logo.webp',
        width: size,
        height: size,
        fit: BoxFit.contain,
        color: eink ? Colors.black : null,
        filterQuality: FilterQuality.medium,
      ),
    );
    if (eink || !glow) return image;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Brand.primary.withValues(alpha: 0.34),
            blurRadius: size * 0.42,
            spreadRadius: -size * 0.10,
            offset: Offset(0, size * 0.10),
          ),
          BoxShadow(
            color: Brand.secondary.withValues(alpha: 0.18),
            blurRadius: size * 0.24,
            spreadRadius: -size * 0.14,
            offset: Offset(0, -size * 0.04),
          ),
        ],
      ),
      child: image,
    );
  }
}

/// 品牌渐变文字：标题、版本号等处用它替代纯色强调。
class BrandGradientText extends StatelessWidget {
  const BrandGradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient,
  });

  final String text;
  final TextStyle? style;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => (gradient ?? Brand.gradient).createShader(bounds),
      child: Text(text, style: style),
    );
  }
}
