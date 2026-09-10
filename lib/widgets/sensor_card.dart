import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'spinning_image.dart';

class SensorCard extends StatelessWidget {
  final String iconAsset;
  final String label;
  final double? value;
  final String unit;
  final int decimals;
  final bool Function(double) isSafe;
  final bool spinning;

  const SensorCard({super.key, required this.iconAsset, required this.label, required this.value, required this.unit, required this.decimals, required this.isSafe, this.spinning = false});

  @override
  Widget build(BuildContext context) {
    final isConnected = value != null && !value!.isNaN;
    final safe = isConnected ? isSafe(value!) : true;
    final color = safe ? AppColors.textPrimary : AppColors.danger;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: safe ? AppColors.border : AppColors.danger.withValues(alpha: 0.4)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: isConnected ? 1.0 : 0.35,
            child: spinning
                ? SpinningImage(asset: iconAsset, size: 40, spinning: isConnected)
                : Image.asset(iconAsset, width: 40, height: 40),
          ),
          const SizedBox(height: 8),
          isConnected
              ? AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(animation), child: child),
                  ),
                  child: Text('${value!.toStringAsFixed(decimals)}$unit',
                      key: ValueKey('${value!.toStringAsFixed(decimals)}$unit'),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                )
              : const Text('Not Connected', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
