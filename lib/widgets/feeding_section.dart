import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/theme.dart';
import '../core/feeding_schedule.dart';
import '../core/firmware_spec.dart';
import '../services/local_feeding_provider.dart';
import '../services/device_provider.dart';
import 'feeding_calendar.dart';
import 'feeding_date_editor.dart';
import 'feeding_overview.dart';
import 'motion.dart';

/// Feeding controls, Supabase-backed:
///   - a dose dropdown (5/10/15/20/25/30 g) — the only amounts the
///     firmware has calibrated servo open-times for, from
///     [FirmwareSpec.feedGramOptions]
///   - a ROTATOR SPEED dropdown — the five PWM levels setMotor1() was
///     bench-tested at, from [FirmwareSpec.rotatorSpeeds]
///   - "Feed Now" inserts a one-shot `feed_now` command row
///   - "Choose dates" opens the calendar, then the per-date feed editor
///   - the overview groups saved feeds by date for editing and deletion
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
  int _grams = 10;
  int _rotatorPwm = FirmwareSpec.rotatorDefaultPwm;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocalFeedingProvider>().fetchSchedules();
    });
  }

  Future<void> _onChooseDates(String deviceId) async {
    final dates = await showFeedingCalendar(
      context,
      initialMode: FeedingCalendarMode.multiple,
    );
    if (dates == null || dates.isEmpty || !mounted) return;

    final provider = context.read<LocalFeedingProvider>();
    final result = await showFeedingDateEditor(
      context,
      dates: dates,
      initialByDate: {for (final date in dates) date: <FeedingDraft>[]},
      existing: provider.schedulesForDevice(deviceId),
    );
    if (result == null || !mounted) return;

    final drafts = result.values.expand((rows) => rows).toList();
    if (drafts.isEmpty) return;
    final saved = await runScheduleWrite(
      context,
      failureMessage: 'Could not save feeds. Please try again.',
      write: () => provider.createSchedules(deviceId, drafts),
    );
    if (!saved || !mounted) return;
    _toast('Added ${drafts.length} feed${drafts.length == 1 ? '' : 's'}');
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

        // ── Choose dates for automatic feeding ──
        _Card(
          title: 'Automatic Feeding',
          children: [
            const Text(
              'Choose one or more device dates, then set the feeds for each day.',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            PressableScale(
              key: const Key('feeding-choose-dates'),
              onTap: paired ? () => _onChooseDates(deviceId) : null,
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
                      child: const Icon(LucideIcons.calendarDays,
                          size: 18, color: AppColors.primary),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Choose dates',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            FirmwareSpec.deviceTimezoneLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(LucideIcons.chevronRight,
                        size: 18, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Saved feeds, grouped by date ──
        const FeedingOverview(),
      ],
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
