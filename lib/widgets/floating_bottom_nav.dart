import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/theme.dart';

/// Minimalist glassmorphism floating tab bar - dark frosted green
/// glass, with the active tab highlighted by a perfect circle rather
/// than a rounded rectangle.
class FloatingBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const FloatingBottomNav({super.key, required this.currentIndex, required this.onTap});

  static const _items = [
    (icon: LucideIcons.layoutGrid, label: 'Dashboard'),
    (icon: LucideIcons.slidersHorizontal, label: 'Management'),
    (icon: LucideIcons.barChart3, label: 'Analytics'),
    (icon: LucideIcons.wifi, label: 'Setup'),
    (icon: LucideIcons.bell, label: 'Alerts'),
  ];

  @override
  Widget build(BuildContext context) {
    // Genuinely green glass now - the brand primary color itself,
    // not blended toward black. Still frosted/translucent via the
    // backdrop blur below, just visibly green rather than near-black.
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), offset: const Offset(0, 8), blurRadius: 24)],
            ),
            child: Row(
              children: List.generate(_items.length, (i) {
                final selected = i == currentIndex;
                final item = _items[i];
                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(32),
                    onTap: () {
                      if (i != currentIndex) HapticFeedback.selectionClick();
                      onTap(i);
                    },
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          // Fixed 1:1 width/height + a fully-round
                          // radius makes this a genuine circle, not a
                          // rounded rectangle that happens to look
                          // pill-shaped.
                          color: selected ? Colors.white.withValues(alpha: 0.95) : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(item.icon, color: selected ? AppColors.primary : Colors.white, size: 21),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
