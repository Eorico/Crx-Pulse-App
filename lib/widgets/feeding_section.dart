import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/theme.dart';
import '../core/firmware_spec.dart';
import '../services/local_feeding_provider.dart';
import '../services/device_provider.dart';
import 'motion.dart';

/// Feeding controls, Supabase-backed:
///   - a dose dropdown (5/10/15/20/25/30 g) — the only amounts the
///     firmware has calibrated servo open-times for, from
///     [FirmwareSpec.feedGramOptions]
///   - a ROTATOR SPEED dropdown — the five PWM levels setMotor1() was
///     bench-tested at, from [FirmwareSpec.rotatorSpeeds]
///   - "Feed Now" inserts a one-shot `feed_now` command row
///   - a time picker + "Add Schedule" adds automatic feeding times
///   - each schedule row has an on/off toggle and delete
///
/// Everything writes to Supabase under the signed-in user, tagged with
/// the paired device id, and the ESP32 reads it directly over PostgREST
/// (no server, no Cloud Functions). If no device is paired yet, the
/// controls are disabled with a hint pointing to Device Setup.
///
/// Times are picked, not typed. The old free-text field accepted any
/// `\d\d:\d\d`, so "99:99" saved happily and then never fired: the
/// firmware compares the stored string against its own clock formatted
/// as %02d:%02d, which can never produce an hour above 23.
class LocalFeedingSection extends StatefulWidget {
  const LocalFeedingSection({super.key});

  @override
  State<LocalFeedingSection> createState() => _LocalFeedingSectionState();
}

class _LocalFeedingSectionState extends State<LocalFeedingSection> {
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  int _grams = 10;
  int _rotatorPwm = FirmwareSpec.rotatorDefaultPwm;
  bool _sending = false;

  String get _timeText =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocalFeedingProvider>().fetchSchedules();
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      initialEntryMode: TimePickerEntryMode.dial,
      helpText: 'FEEDING TIME (${FirmwareSpec.deviceTimezoneLabel.toUpperCase()})',
      // The app's global inputDecorationTheme was leaking into the
      // picker's hour/minute fields and mangling them — see
      // AppTheme.timePickerBuilder for the detail.
      builder: AppTheme.timePickerBuilder,
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _onAdd(String deviceId) async {
    final duplicate = context
        .read<LocalFeedingProvider>()
        .schedules
        .any((s) => s.time == _timeText);
    if (duplicate) {
      _toast('There is already a schedule at $_timeText');
      return;
    }

    await context.read<LocalFeedingProvider>().createSchedule(
          deviceId,
          _timeText,
          _grams,
          rotatorPwm: _rotatorPwm,
        );
    _toast('Schedule added — ${_grams}g at $_timeText');
  }

  Future<void> _onFeedNow(String deviceId) async {
    setState(() => _sending = true);
    final ok = await context
        .read<LocalFeedingProvider>()
        .feedNow(deviceId, _grams, rotatorPwm: _rotatorPwm);
    if (!mounted) return;
    setState(() => _sending = false);
    _toast(ok
        ? 'Feeding ${_grams}g — the device picks this up within a few seconds'
        : 'Could not send feed command');
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final feeding = context.watch<LocalFeedingProvider>();
    final device = context.watch<DeviceProvider>();
    final deviceId = device.deviceId;
    final paired = deviceId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pairing hint / info note — cross-fades between the two states.
        SwapIn(
          swapKey: paired,
          child: paired ? const _DeviceNote() : const _PairingWarning(),
        ),

        // ── Amount + rotator speed + Feed Now ──
        _Card(
          title: 'Feed Amount',
          children: [
            _LabelledDropdown<int>(
              label: 'Dose',
              value: _grams,
              items: [
                for (final g in FirmwareSpec.feedGramOptions)
                  DropdownMenuItem<int>(value: g, child: Text('$g grams')),
              ],
              onChanged: (v) => setState(() => _grams = v ?? _grams),
            ),
            const SizedBox(height: 12),

            // Rotator speed. The DC motor runs for a fixed 2 s after
            // every feed; this is how fast.
            _LabelledDropdown<int>(
              label: 'Rotator speed (DC motor)',
              value: _rotatorPwm,
              items: [
                for (final s in FirmwareSpec.rotatorSpeeds)
                  DropdownMenuItem<int>(
                    value: s.pwm,
                    child: Text(s.pwm == 0
                        ? '${s.label} — no rotation'
                        : '${s.label}  ·  PWM ${s.pwm}'),
                  ),
              ],
              onChanged: (v) => setState(() => _rotatorPwm = v ?? _rotatorPwm),
            ),

            const SizedBox(height: 10),
            // Explains what the settings actually do on the device, and
            // re-animates whenever either changes.
            SwapIn(
              swapKey: '$_grams-$_rotatorPwm',
              duration: AppMotion.fast,
              child: Text(
                _rotatorPwm == 0
                    ? 'Door opens ${FirmwareSpec.feedOpenMs[_grams]} ms. '
                        'The rotator stays off.'
                    : 'Door opens ${FirmwareSpec.feedOpenMs[_grams]} ms, then the '
                        'rotator runs at ${FirmwareSpec.rotatorSpeedForPwm(_rotatorPwm).label} '
                        'for ${(FirmwareSpec.rotatorRun.inMilliseconds / 1000).toStringAsFixed(1)}s — '
                        'about ${(FirmwareSpec.feedCycleFor(_grams).inMilliseconds / 1000).toStringAsFixed(1)}s in total.',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11, height: 1.35),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (paired && !_sending) ? () => _onFeedNow(deviceId) : null,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.restaurant_rounded, size: 18),
                label: Text(_sending ? 'Sending…' : 'Feed Now'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Add a scheduled time ──
        _Card(
          title: 'Add Automatic Feeding Time',
          children: [
            const Text('Time · 24h · ${FirmwareSpec.deviceTimezoneLabel}',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _TimeField(time: _timeText, onTap: _pickTime),
            const SizedBox(height: 10),
            SwapIn(
              swapKey: '$_grams-$_rotatorPwm-$_timeText',
              duration: AppMotion.fast,
              child: Text(
                'Will feed $_grams g at $_timeText every day, '
                'rotator ${FirmwareSpec.rotatorSpeedForPwm(_rotatorPwm).label}.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: paired ? () => _onAdd(deviceId) : null,
                icon: const Icon(LucideIcons.plus, size: 18),
                label: const Text('Add Schedule'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Schedule list ──
        AnimatedSize(
          duration: AppMotion.normal,
          curve: AppMotion.smooth,
          alignment: Alignment.topCenter,
          child: feeding.isLoading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
              : feeding.schedules.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No feeding times yet.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: FadeSlideIn.stagger(
                        [
                          for (final s in feeding.schedules)
                            _ScheduleRow(key: ValueKey(s.id), schedule: s),
                        ],
                        from: const Offset(-0.08, 0),
                      ),
                    ),
        ),
      ],
    );
  }
}

/// The time trigger.
///
/// Laid out as a two-line block rather than one cramped row: the old
/// version put an icon, an 18px bold time, a Spacer and an 11px "Tap to
/// change" on a single line inside a padded well, which left the hint
/// fighting the time for space on a narrow phone. Now the time owns its
/// line and the hint sits under it, so neither can be squeezed.
class _TimeField extends StatelessWidget {
  final String time;
  final VoidCallback onTap;
  const _TimeField({required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.985,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3EF),
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.clock, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            // Flexible, so a long locale string can never overflow the
            // row — it ellipsises instead.
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwapIn(
                    swapKey: time,
                    duration: AppMotion.fast,
                    child: Text(
                      time,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: 1,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const Text(
                    'Tap to change',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// A labelled dropdown in the app's clay well style. Shared so the dose
/// and the rotator speed cannot drift apart visually.
class _LabelledDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _LabelledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(16),
              icon: const Icon(LucideIcons.chevronDown,
                  size: 18, color: AppColors.textSecondary),
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Card({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _PairingWarning extends StatelessWidget {
  const _PairingWarning();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
          SizedBox(width: 8),
          Expanded(
              child: Text('Pair your ESP32 in Device Setup to enable feeding.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12, height: 1.3))),
        ]),
      );
}

class _DeviceNote extends StatelessWidget {
  const _DeviceNote();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(LucideIcons.info, size: 14, color: AppColors.primary),
          SizedBox(width: 8),
          Expanded(
              child: Text(
                  'Scheduled feeds run on the device itself, so they work even '
                  'when the app is closed.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 11, height: 1.3))),
        ]),
      );
}

/// One schedule row. Swipe it away to delete, toggle to pause — both
/// routes go to the same provider, and the row dims while paused so an
/// inactive schedule is obvious at a glance.
class _ScheduleRow extends StatelessWidget {
  final FeedingSchedule schedule;
  const _ScheduleRow({super.key, required this.schedule});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<LocalFeedingProvider>();
    final speed = FirmwareSpec.rotatorSpeedForPwm(schedule.rotatorPwm);

    return Dismissible(
      key: ValueKey('dismiss-${schedule.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => provider.deleteSchedule(schedule.id),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
            color: AppColors.danger, borderRadius: BorderRadius.circular(14)),
        child: const Icon(LucideIcons.trash2, color: Colors.white, size: 20),
      ),
      child: AnimatedOpacity(
        duration: AppMotion.normal,
        opacity: schedule.active ? 1.0 : 0.55,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppShadows.card),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(schedule.time,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 0.3)),
                    Text(
                      '${schedule.grams}g · rotator ${speed.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: schedule.active,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => provider.toggleSchedule(schedule.id, v),
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash2, color: AppColors.danger, size: 18),
                onPressed: () => provider.deleteSchedule(schedule.id),
                tooltip: 'Delete schedule',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
