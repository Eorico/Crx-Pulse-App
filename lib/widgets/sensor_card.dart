import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'motion.dart';
import 'spinning_image.dart';

/// One live sensor reading.
///
/// Motion does real work here rather than being decoration: the value
/// counts to its new reading (so a change registers as movement, not a
/// flicker), the card's border and tint animate when a reading crosses
/// out of its safe range, the icon dims when the sensor goes away, and
/// the whole card depresses under a finger so it reads as a physical
/// clay tile.
class SensorCard extends StatelessWidget {
  final String iconAsset;
  final String label;
  final double? value;
  final String unit;
  final int decimals;
  final bool Function(double) isSafe;
  final bool spinning;

  /// Optional small line under the value (e.g. the turbidity status
  /// word "Clear" / "Turbid"). Shown only when a value is present.
  final String? subtitle;

  /// Optional tap handler — when given, the card becomes pressable.
  final VoidCallback? onTap;

  const SensorCard({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.value,
    required this.unit,
    required this.decimals,
    required this.isSafe,
    this.spinning = false,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = value != null && !value!.isNaN;
    final safe = isConnected ? isSafe(value!) : true;
    final color = safe ? AppColors.textPrimary : AppColors.danger;

    final card = AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.smooth,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // A breached reading warms the whole tile, not just its number,
        // so it is visible from across the room.
        color: safe
            ? AppColors.surface
            : Color.lerp(AppColors.surface, AppColors.danger, 0.06)!,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: safe ? AppColors.border : AppColors.danger.withValues(alpha: 0.4),
          width: safe ? 1 : 1.4,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedOpacity(
            duration: AppMotion.normal,
            curve: AppMotion.smooth,
            opacity: isConnected ? 1.0 : 0.35,
            // A live, out-of-range reading gets a slow red halo — the
            // one place on this card that moves on its own.
            child: PulseHalo(
              color: AppColors.danger,
              active: isConnected && !safe,
              child: spinning
                  ? SpinningImage(asset: iconAsset, size: 40, spinning: isConnected)
                  : Image.asset(iconAsset, width: 40, height: 40),
            ),
          ),
          const SizedBox(height: 8),
          // Swapping between a reading and "Not Connected" cross-fades;
          // while a reading is present it counts to each new value.
          SwapIn(
            swapKey: isConnected,
            child: isConnected
                ? AnimatedNumber(
                    value: value!,
                    decimals: decimals,
                    suffix: unit,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  )
                : const Text(
                    'Not Connected',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
          ),
          // The status word gets its own swap so "Clear" -> "Turbid"
          // animates independently of the number above it.
          AnimatedSize(
            duration: AppMotion.normal,
            curve: AppMotion.smooth,
            child: (isConnected && subtitle != null && subtitle!.isNotEmpty)
                ? Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SwapIn(
                      swapKey: subtitle,
                      duration: AppMotion.fast,
                      child: Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );

    if (onTap == null) return card;
    return PressableScale(onTap: onTap, child: card);
  }
}
