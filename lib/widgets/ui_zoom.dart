import 'package:flutter/material.dart';

/// 把整棵 UI 按 [scale] 放大/缩小。
///
/// 做法是把逻辑视口按比例缩小（或放大）后整体缩放回窗口尺寸：
/// - 布局按缩放后的逻辑宽度重排，断点、栅格列数都会自然跟着变；
/// - `MediaQuery.size/padding/viewInsets` 同步换成缩放后的逻辑值，
///   弹层、播放器与安全区不会按原始窗口尺寸算错；
/// - [FittedBox] 负责最终缩放与命中测试换算，文字仍按矢量绘制，不会糊。
///
/// `scale == 1` 时直接返回原树，不增加任何图层或重排开销。
class UiZoom extends StatelessWidget {
  const UiZoom({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if ((scale - 1).abs() < 0.001) return child;
    // builder 位于 MediaQuery 之下；万一未来被挪到更外层，退回原树而不是崩。
    final media = MediaQuery.maybeOf(context);
    if (media == null) return child;
    final base = media.size;
    final logical = Size(base.width / scale, base.height / scale);
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: logical.width,
        height: logical.height,
        child: MediaQuery(
          data: media.copyWith(
            size: logical,
            padding: _scaled(media.padding, scale),
            viewPadding: _scaled(media.viewPadding, scale),
            viewInsets: _scaled(media.viewInsets, scale),
          ),
          child: child,
        ),
      ),
    );
  }

  static EdgeInsets _scaled(EdgeInsets value, double scale) => EdgeInsets.fromLTRB(
    value.left / scale,
    value.top / scale,
    value.right / scale,
    value.bottom / scale,
  );
}
