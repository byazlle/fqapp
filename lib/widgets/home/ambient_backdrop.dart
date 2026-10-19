import 'package:flutter/material.dart';

import '../../services/brand.dart';
import 'home_design.dart';

/// How far the wash is allowed to travel over the whole feed. The contour
/// drifts at [_washDrift] of the scroll offset, so the maximum travel is
/// [_washScrollRange] * [_washDrift].
const double _washScrollRange = 900;
const double _washDrift = 0.08;
const double _maxTravel = _washScrollRange * _washDrift;

/// A quiet wash of warm light. Scrolling moves the contour, not a ticker.
///
/// The wash is painted once into a layer of its own and then only *translated*
/// while the feed scrolls. Re-painting the gradient on every scroll frame
/// costs a full-viewport raster plus a fresh shader allocation per frame, for a
/// picture that never actually changes -- and the feed already repaints its own
/// layer, so the backdrop was doubling the work of every scroll frame.
///
/// The painted layer is grown past the bottom of the viewport so translating it
/// upwards can never expose an unpainted seam at the bottom edge. The page
/// background itself comes from the enclosing [Scaffold], which paints the same
/// [HomePalette.canvas] colour, so the grown area blends in exactly.
class AmbientBackdrop extends StatelessWidget {
  final ScrollController scroll;

  const AmbientBackdrop({super.key, required this.scroll});

  /// How far the contour has drifted for the current scroll offset.
  static double _travel(ScrollController scroll) {
    if (!scroll.hasClients) return 0;
    return scroll.offset.clamp(0.0, _washScrollRange) * _washDrift;
  }

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: -_maxTravel,
            // Outer boundary keeps the per-frame transform out of the feed's
            // own layer; the inner one is the cached wash the transform moves.
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: scroll,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _PaperLightPainter(dark: palette.dark),
                  ),
                ),
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, reducedMotion ? 0 : -_travel(scroll)),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 首页的环境光：三团极光色雾（紫 / 青 / 品红），随滚动产生轻微位移。
/// 只画半透明径向渐变，不挂 BackdropFilter——滚动时零额外采样开销。
class _PaperLightPainter extends CustomPainter {
  final bool dark;

  const _PaperLightPainter({required this.dark});

  /// (对齐点, 半径系数, 颜色, 浅色透明度, 深色透明度)
  static const List<(Alignment, double, Color, double, double)> _washes = [
    (Alignment(1.05, -0.55), 0.95, Brand.primary, 0.10, 0.22),
    (Alignment(-0.85, 0.35), 0.85, Brand.secondary, 0.075, 0.14),
    (Alignment(0.35, 1.15), 0.70, Brand.highlight, 0.05, 0.10),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (align, scale, color, lightAlpha, darkAlpha) in _washes) {
      final radius = size.width * scale;
      if (radius <= 0) continue;
      final center = Offset(
        align.x * size.width,
        align.y * size.height,
      );
      final alpha = dark ? darkAlpha : lightAlpha;
      final shader = RadialGradient(
        colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_PaperLightPainter oldDelegate) => dark != oldDelegate.dark;
}
