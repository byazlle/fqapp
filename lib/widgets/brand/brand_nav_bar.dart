import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../services/brand.dart';
import 'glass.dart';

/// 一级导航的一条目的地。
class BrandNavDestination {
  const BrandNavDestination({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// 顶部悬浮吸顶导航。
///
/// 设计约束（来自用户反馈：切到「短剧」时导航颜色会变、看不懂）：
/// * **配色恒定**：不管当前页是浅色还是黑底视频流，导航永远是浅色玻璃 +
///   黑色文字，选中项是一块纯黑胶囊 + 白字。页面背景不参与导航配色，
///   所以点哪个 tab 都不会「变色」。
/// * **悬浮吸顶**：壳层把它固定在最顶层，内容整体下移一个导航高度，
///   任何页面滚动时导航都不动。
/// * 墨水屏模式退化为不透明白底 + 黑色胶囊，不再有模糊层。
class BrandNavBar extends StatelessWidget {
  const BrandNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    this.eink = false,
    this.showBrand = true,
  });

  final List<BrandNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool eink;
  final bool showBrand;

  /// 导航条本身的高度（不含外边距）。壳层用它给内容让位。
  static const double height = 54;

  /// 导航占用的总高度：条高 + 上下留白。内容区按它整体下移。
  static const double occupiedHeight = height + 12;

  static const Color _ink = Color(0xFF14161B);

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      height: height,
      decoration: BoxDecoration(
        color: eink ? Colors.white : Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: eink ? Colors.black : Colors.white.withValues(alpha: 0.72),
          width: eink ? 1.4 : 1,
        ),
        boxShadow: eink
            ? const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0xFF7A0B14).withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          // 墨水屏没有模糊代价可付，直接返回面板本体。
          filter: eink
              ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
              : ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Row(
            children: [
              if (showBrand) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 14, right: 12),
                  child: _brandBlock(),
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: Colors.black.withValues(alpha: 0.08),
                ),
              ],
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      for (var i = 0; i < destinations.length; i++)
                        _item(destinations[i], i),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return panel;
  }

  Widget _brandBlock() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: 26, radius: 8, eink: eink, glow: false),
        const SizedBox(width: 8),
        Text(
          Brand.name,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: _ink,
          ),
        ),
      ],
    );
  }

  Widget _item(BrandNavDestination destination, int index) {
    final selected = index == selectedIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('nav_item_${destination.label}'),
          borderRadius: BorderRadius.circular(13),
          onTap: () => onSelect(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? _ink : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  destination.icon,
                  size: 17,
                  color: selected
                      ? Colors.white
                      : _ink.withValues(alpha: 0.62),
                ),
                const SizedBox(width: 6),
                Text(
                  destination.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? Colors.white
                        : _ink.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
