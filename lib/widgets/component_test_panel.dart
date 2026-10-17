import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/theme.dart';
import '../core/firmware_spec.dart';
import '../services/device_test_provider.dart';
import 'motion.dart';

/// Servo and DC-motor controls for Test Components.
///
/// Each button queues a row in `commands`; the ESP32 acts on it at its
/// next poll (~5 s). The copy says so rather than implying the actuator
/// moves the instant you tap — there is no faster path from the phone
/// to the device, and a button that looks instant but isn't reads as
/// broken hardware.
///
/// Watch the console above to see the device acknowledge each one.
class ComponentTestPanel extends StatelessWidget {
  /// Null when nothing is paired — every control is then disabled.
  final String? deviceId;

  const ComponentTestPanel({super.key, required this.deviceId});

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final test = context.watch<DeviceTestProvider>();
    final id = deviceId;
    final enabled = id != null && !test.sending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: FadeSlideIn.stagger([
        // ── Feeder servo ──
        _TestCard(
          icon: LucideIcons.rotate3d,
          title: 'Feeder Servo',
          subtitle: 'Open ${FirmwareSpec.servoOpenAngle}° · '
              'Closed ${FirmwareSpec.servoClosedAngle}°',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: enabled
                          ? () async {
                              await context.read<DeviceTestProvider>().openServo(id);
                              if (context.mounted) _toast(context, 'Servo open queued');
                            }
                          : null,
                      icon: const Icon(LucideIcons.arrowUpFromLine, size: 16),
                      label: const Text('Open'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: enabled
                          ? () async {
                              await context.read<DeviceTestProvider>().closeServo(id);
                              if (context.mounted) _toast(context, 'Servo close queued');
                            }
                          : null,
                      icon: const Icon(LucideIcons.arrowDownToLine, size: 16),
                      label: const Text('Close'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SafetyNote(
                'The door drops feed while it is open, so the device closes it '
                'by itself after ${FirmwareSpec.servoTestAutoClose.inSeconds}s.',
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── DC rotator ──
        _TestCard(
          icon: LucideIcons.fan,
          title: 'DC Motor (Rotator)',
          subtitle: 'Motor 1 · PWM on the L298N',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Speed adjustment: the five levels setMotor1() was
              // bench-tested at, as a slider with a stop on each.
              Row(
                children: [
                  const Text('Speed',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary)),
                  const Spacer(),
                  SwapIn(
                    swapKey: test.motorPwm,
                    duration: AppMotion.fast,
                    child: Text(
                      '${FirmwareSpec.rotatorSpeedForPwm(test.motorPwm).label}'
                      '  ·  PWM ${test.motorPwm}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              Slider(
                value: FirmwareSpec.rotatorSpeeds
                    .indexWhere((s) => s.pwm == test.motorPwm)
                    .clamp(0, FirmwareSpec.rotatorSpeeds.length - 1)
                    .toDouble(),
                min: 0,
                max: (FirmwareSpec.rotatorSpeeds.length - 1).toDouble(),
                divisions: FirmwareSpec.rotatorSpeeds.length - 1,
                label: FirmwareSpec.rotatorSpeedForPwm(test.motorPwm).label,
                activeColor: AppColors.primary,
                onChanged: id == null
                    ? null
                    : (v) => context
                        .read<DeviceTestProvider>()
                        .setMotorPwm(FirmwareSpec.rotatorSpeeds[v.round()].pwm),
              ),
              // Tick labels, so the stops are readable without dragging.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final s in FirmwareSpec.rotatorSpeeds)
                      Text(s.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: s.pwm == test.motorPwm
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: s.pwm == test.motorPwm
                                ? AppColors.primary
                                : AppColors.textMuted,
                          )),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: enabled
                          ? () async {
                              await context.read<DeviceTestProvider>().runMotor(id);
                              if (context.mounted) {
                                _toast(context,
                                    test.motorPwm == 0 ? 'Stop queued' : 'Run queued');
                              }
                            }
                          : null,
                      icon: const Icon(LucideIcons.play, size: 16),
                      label: const Text('Run'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: enabled
                          ? () async {
                              await context.read<DeviceTestProvider>().stopMotor(id);
                              if (context.mounted) _toast(context, 'Stop queued');
                            }
                          : null,
                      icon: const Icon(LucideIcons.square, size: 16),
                      label: const Text('Stop'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SafetyNote(
                'The device stops the motor by itself after '
                '${FirmwareSpec.motorTestTimeout.inSeconds}s, so a test cannot '
                'leave it running.',
              ),
            ],
          ),
        ),

        // ── last action / error ──
        AnimatedSize(
          duration: AppMotion.normal,
          curve: AppMotion.smooth,
          alignment: Alignment.topCenter,
          child: (test.errorMessage != null || test.lastAction != null)
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: test.errorMessage != null
                          ? AppColors.danger.withValues(alpha: 0.10)
                          : AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Icon(
                        test.errorMessage != null
                            ? LucideIcons.alertCircle
                            : LucideIcons.check,
                        size: 14,
                        color: test.errorMessage != null
                            ? AppColors.danger
                            : AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          test.errorMessage ?? 'Queued: ${test.lastAction}',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: test.errorMessage != null
                                ? AppColors.danger
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ]),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

class _TestCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _TestCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11, height: 1.3)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SafetyNote extends StatelessWidget {
  final String text;
  const _SafetyNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.shieldCheck, size: 12, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 10.5, height: 1.35)),
        ),
      ],
    );
  }
}
