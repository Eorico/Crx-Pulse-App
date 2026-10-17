import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Wraps any header widget so it can be used as a PINNED sliver -
/// stays visible at the top while the rest of the screen scrolls
/// underneath it, instead of scrolling away with the content. One
/// shared delegate used across every screen rather than each screen
/// reimplementing SliverPersistentHeaderDelegate itself.
///
/// The header also lifts as content passes beneath it: its shadow
/// deepens and its bottom corners tighten slightly once you start
/// scrolling, so it reads as a surface the content slides under rather
/// than a band painted on top.
class StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  StickyHeaderDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // 0 at rest, 1 once ~40px of content has gone under the header.
    final lift = (shrinkOffset / 40).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(24 - 6 * lift),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13 + 0.12 * lift),
            offset: Offset(0, 4 + 2 * lift),
            blurRadius: 14 + 8 * lift,
          ),
        ],
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant StickyHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}
