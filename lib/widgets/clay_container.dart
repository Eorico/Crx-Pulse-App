import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'motion.dart';

/// A reusable Claymorphism surface: a soft, inflated, borderless panel
/// with the two-tone clay shadow. Drop it in anywhere you'd otherwise
/// hand-roll a `Container(decoration: BoxDecoration(... AppShadows.card))`.
///
/// Example — give the Home hero card the clay look without changing its
/// contents:
///
///   ClayContainer(
///     color: AppColors.primary,
///     borderRadius: 28,
///     padding: const EdgeInsets.all(20),
///     child: Row(...),
///   )
class ClayContainer extends StatelessWidget {
  final Widget child;
  final Color color;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? width;

  /// When true the shadow direction flips to read as inset/pressed —
  /// handy for a selected chip or a tapped tile.
  final bool pressed;

  /// A gentler shadow for small rows/chips.
  final bool soft;

  /// When given, the surface becomes tappable and physically depresses
  /// under the finger — clay that can be pushed.
  final VoidCallback? onTap;

  const ClayContainer({
    super.key,
    required this.child,
    this.color = AppColors.clayFill,
    this.borderRadius = AppRadius.card,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.width,
    this.pressed = false,
    this.soft = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shadows = pressed
        ? AppShadows.clayPressed
        : soft
            ? AppShadows.claySoft
            : AppShadows.clay;

    final surface = AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.smooth,
      width: width,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows,
      ),
      child: child,
    );

    if (onTap == null) return surface;
    return PressableScale(onTap: onTap, pressedScale: 0.975, child: surface);
  }
}
