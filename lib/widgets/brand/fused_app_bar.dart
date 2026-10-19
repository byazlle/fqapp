import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// 滚动进度计量：包在页面 Scaffold **外层**，收集子树里滚动视图的通知，
/// 把 0..1 的进度交给下面的 [FusedAppBar]。
///
/// 放在外层而不是 body 里，是因为 AppBar 与 body 是兄弟节点：只有共同的
/// 祖先才能既收到 body 的滚动通知、又被 AppBar 通过 InheritedNotifier 读到。
class FusedScrollMeter extends StatefulWidget {
  const FusedScrollMeter({super.key, required this.child});

  final Widget child;

  /// 滚过多少像素算「完全贴合」：比顶栏高度小一点，手指一动就有反馈。
  static const double span = 48.0;

  @override
  State<FusedScrollMeter> createState() => _FusedScrollMeterState();
}

class _FusedScrollMeterState extends State<FusedScrollMeter> {
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  bool _onScroll(ScrollNotification notification) {
    // 只看最内层滚动视图：嵌套的横向列表/内层 Tab 不驱动顶栏。
    if (notification.depth != 0) return false;
    final pixels = notification.metrics.pixels;
    final next = (pixels / FusedScrollMeter.span).clamp(0.0, 1.0);
    if ((_progress.value - next).abs() > 0.01) _progress.value = next;
    return false;
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: FusedScrollScope(notifier: _progress, child: widget.child),
    );
  }
}

/// [FusedScrollMeter] 与 [FusedAppBar] 之间的进度通道。
class FusedScrollScope extends InheritedNotifier<ValueNotifier<double>> {
  const FusedScrollScope({
    super.key,
    required ValueNotifier<double> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// 当前滚动贴合度（0 = 顶栏完全透明地躺在内容上，1 = 完全成形）。
  /// 页面没有套 [FusedScrollMeter] 时恒为 0，行为退化为普通透明顶栏。
  static double progressOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FusedScrollScope>()
          ?.notifier
          ?.value ??
      0;
}

/// 与内容融为一体的标题栏。
///
/// 之前顶栏与内容是两块独立的东西，只是底色相同：顶栏永远是一条自己的
/// 带子（有底色、有边界），内容在它下面另起一摊。这里改成——
///
/// * **静止时**：顶栏没有底色、没有分割线、没有阴影，标题直接坐在内容
///   的底色上，看起来就是内容的第一行；
/// * **滚动后**：内容从标题栏底下穿过，标题栏才从「内容自己」里浮出来——
///   底色取页面画布色并对穿过的内容做实时模糊（BackdropFilter），下边线
///   也随滚动淡入。所以它的材质来自内容本身，而不是一块额外的板子。
///
/// 用法：把页面最外层包一层 [FusedScrollMeter]，再把 `AppBar` 换成
/// `FusedAppBar`，其余参数（title / actions / leading / bottom）照原样传。
class FusedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FusedAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.centerTitle,
    this.automaticallyImplyLeading = true,
    this.titleSpacing,
    this.leadingWidth,
    this.toolbarHeight,
    this.foregroundColor,
    this.canvas,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  /// 为 null 时沿用主题里的 AppBar 配置（现为左对齐）。
  final bool? centerTitle;
  final bool automaticallyImplyLeading;
  final double? titleSpacing;
  final double? leadingWidth;
  final double? toolbarHeight;
  final Color? foregroundColor;

  /// 页面画布色：顶栏的材质取自它，和页面底面完全同色。
  /// 不传就退化为主题里的 `scaffoldBackgroundColor`。
  final Color? canvas;

  /// 与 `AppBarTheme.toolbarHeight` 对齐（app_theme.dart 里是 52）。
  static const double defaultToolbarHeight = 52;

  @override
  Size get preferredSize => Size.fromHeight(
    (toolbarHeight ?? defaultToolbarHeight) +
        (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final progress = FusedScrollScope.progressOf(context);
    final base = canvas ?? Theme.of(context).scaffoldBackgroundColor;
    final bar = AppBar(
      title: title,
      actions: actions,
      leading: leading,
      bottom: bottom,
      centerTitle: centerTitle,
      automaticallyImplyLeading: automaticallyImplyLeading,
      titleSpacing: titleSpacing,
      leadingWidth: leadingWidth,
      toolbarHeight: toolbarHeight,
      foregroundColor: foregroundColor,
      // 静止时完全透明：标题与内容共用一块底，看不出「一条栏」。
      backgroundColor: progress <= 0.01
          ? Colors.transparent
          : base.withValues(alpha: 0.55 + 0.4 * progress),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      // 分割线也随滚动淡入：静止时连这条线都没有。
      shape: progress <= 0.01
          ? null
          : Border(
              bottom: BorderSide(
                color: base.withValues(alpha: 0.10 * progress),
                width: 1,
              ),
            ),
    );
    // 模糊强度随进度长出来；进度为 0 时不挂 BackdropFilter，省掉一次采样。
    if (progress <= 0.01) return bar;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14 * progress, sigmaY: 14 * progress),
        child: bar,
      ),
    );
  }
}
