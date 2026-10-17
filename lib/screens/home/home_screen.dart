import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/sensor_icons.dart';
import '../../core/firmware_spec.dart';
import '../../services/local_esp32_service.dart';
import '../../services/local_analytics_provider.dart';
import '../../services/local_notification_provider.dart';
import '../../widgets/connection_cpu_indicator.dart';
import '../../widgets/spinning_image.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/motion.dart';
import '../../widgets/sticky_header_delegate.dart';

/// Dashboard tab — a genuine statistical overview rather than just live
/// current values: min/max/avg trends and a system activity summary.
/// Header is pinned/sticky via CustomScrollView.
///
/// Units here come from [FirmwareSpec] and match what the device
/// actually sends: ammonia is mg/L (it was mislabelled ppm) and
/// turbidity is a percentage (it was mislabelled NTU).
class LocalHomeScreen extends StatefulWidget {
  const LocalHomeScreen({super.key});

  @override
  State<LocalHomeScreen> createState() => _LocalHomeScreenState();
}

class _LocalHomeScreenState extends State<LocalHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocalAnalyticsProvider>().fetchHistory(hoursBack: 24);
      context.read<LocalNotificationProvider>().fetchNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final esp32 = context.watch<LocalEsp32Service>();
    final analytics = context.watch<LocalAnalyticsProvider>();
    final notifications = context.watch<LocalNotificationProvider>();
    final connected = esp32.state == Esp32ConnectionState.connected;

    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: FadeIn(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              esp32.startPolling();
              await context.read<LocalAnalyticsProvider>().fetchHistory(hoursBack: 24);
            },
            child: CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: StickyHeaderDelegate(
                    height: 68,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text('Crx-Pulse',
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.5)),
                          ConnectionCpuIndicator(state: esp32.state),
                        ],
                      ),
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                  sliver: SliverList.list(children: [
                    const Text('Live pond overview',
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),

                    // Per the explicit requirement: when the device
                    // isn't being tracked, NO last reading is shown —
                    // every value is cleared and reads "Not Connected".
                    // This banner makes that state explicit at the top
                    // of the dashboard, and now slides open/shut rather
                    // than jumping the layout.
                    AnimatedSize(
                      duration: AppMotion.normal,
                      curve: AppMotion.smooth,
                      alignment: Alignment.topCenter,
                      child: connected
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                    color: AppColors.danger.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(14)),
                                child: const Row(children: [
                                  Icon(Icons.wifi_off_rounded, size: 15, color: AppColors.danger),
                                  SizedBox(width: 8),
                                  Expanded(
                                      child: Text(
                                          'Not Connected — no live readings from your device',
                                          style: TextStyle(
                                              color: AppColors.danger,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700))),
                                ]),
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),

                    // ── SYSTEM STATUS - hero card ──
                    FadeSlideIn(
                      from: const Offset(0, 0.10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 32, 85, 1),
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          boxShadow: AppShadows.clay,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // The mascot swaps on connection change and
                            // breathes gently while it's live, so the
                            // hero card is never completely static.
                            Breathing(
                              active: connected,
                              child: SwapIn(
                                swapKey: connected,
                                child: Image.asset(
                                  connected
                                      ? 'assets/images/mascot/wave-anim.gif'
                                      : 'assets/images/mascot/no-connection-anim.gif',
                                  width: 88,
                                  height: 88,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('STATUS',
                                      style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.65),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 2)),
                                  const SizedBox(height: 6),
                                  SwapIn(
                                    swapKey: connected,
                                    child: Text(
                                      connected ? 'All Systems Go' : 'Standing By',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.5),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(mainAxisSize: MainAxisSize.min, children: [
                                    SpinningImage(
                                        asset: SensorIcons.fan,
                                        size: 18,
                                        spinning: esp32.fanActive),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        esp32.fanActive
                                            ? 'Cooling active · ${esp32.fanDutyPercent}%'
                                            : 'Cooling idle',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    const _SectionLabel(title: "Today's Summary"),
                    Row(children: [
                      Expanded(
                        child: FadeSlideIn(
                          delay: const Duration(milliseconds: 90),
                          child: _SummaryStatCard(
                            label: 'Readings Logged',
                            value: analytics.history.length,
                            iconAsset: SensorIcons.stats,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FadeSlideIn(
                          delay: const Duration(milliseconds: 145),
                          child: _SummaryStatCard(
                            label: 'Active Alerts',
                            value: notifications.unreadCount,
                            iconAsset: SensorIcons.bell,
                            highlight: notifications.unreadCount > 0,
                          ),
                        ),
                      ),
                    ]),

                    const SizedBox(height: 20),
                    const _SectionLabel(title: '24-Hour Range'),
                    // Units below are the device's own: mg/L for
                    // ammonia, % for turbidity.
                    ...FadeSlideIn.stagger(
                      [
                        _RangeStatRow(
                          iconAsset: SensorIcons.ph,
                          label: 'pH',
                          unit: '',
                          values: analytics.history.map((h) => h.ph).whereType<double>().toList(),
                          decimals: 1,
                        ),
                        _RangeStatRow(
                          iconAsset: SensorIcons.ammonia,
                          label: 'Ammonia',
                          unit: FirmwareSpec.ammoniaUnit,
                          values: analytics.history.map((h) => h.ammonia).whereType<double>().toList(),
                          decimals: 2,
                        ),
                        _RangeStatRow(
                          iconAsset: SensorIcons.turbidity,
                          label: 'Turbidity',
                          unit: '%',
                          values: analytics.history.map((h) => h.turbidity).whereType<double>().toList(),
                          decimals: 1,
                        ),
                        _RangeStatRow(
                          iconAsset: SensorIcons.waterTemp,
                          label: 'Water Temp',
                          unit: '°C',
                          values: analytics.history.map((h) => h.waterTempC).whereType<double>().toList(),
                          decimals: 1,
                        ),
                      ],
                      initialDelay: const Duration(milliseconds: 190),
                      from: const Offset(-0.04, 0.06),
                    ),

                    if (esp32.lastUpdated != null) ...[
                      const SizedBox(height: 20),
                      Center(
                        child: SwapIn(
                          swapKey: esp32.lastUpdated,
                          duration: AppMotion.fast,
                          child: Text(
                            'Updated ${_hms(esp32.lastUpdated!)}',
                            style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _hms(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 8),
      child: Text(title.toUpperCase(),
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1)),
    );
  }
}

/// Quick "at a glance" numbers — readings logged, active alert count.
/// The count animates between values, so a new alert arriving is
/// visible as movement rather than a silent digit change.
class _SummaryStatCard extends StatelessWidget {
  final String label;
  final int value;
  final String iconAsset;
  final bool highlight;
  const _SummaryStatCard({
    required this.label,
    required this.value,
    required this.iconAsset,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.smooth,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight ? AppColors.warning.withValues(alpha: 0.1) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
        border: highlight
            ? Border.all(color: AppColors.warning.withValues(alpha: 0.4))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PulseHalo(
            color: AppColors.warning,
            active: highlight,
            maxRadius: 10,
            child: Image.asset(iconAsset, width: 28, height: 28),
          ),
          const SizedBox(height: 8),
          AnimatedNumber(
            value: value.toDouble(),
            decimals: 0,
            duration: AppMotion.normal,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: highlight ? AppColors.warning : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Min/Avg/Max row for a single sensor over the fetched history window
/// — the actual statistical overview, not just the instantaneous value.
class _RangeStatRow extends StatelessWidget {
  final String iconAsset;
  final String label;
  final String unit;
  final List<double> values;
  final int decimals;
  const _RangeStatRow({
    required this.iconAsset,
    required this.label,
    required this.unit,
    required this.values,
    required this.decimals,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = values.isNotEmpty;
    final min = hasData ? values.reduce((a, b) => a < b ? a : b) : null;
    final max = hasData ? values.reduce((a, b) => a > b ? a : b) : null;
    final avg = hasData ? values.reduce((a, b) => a + b) / values.length : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppShadows.card),
      child: Row(
        children: [
          Image.asset(iconAsset, width: 28, height: 28),
          const SizedBox(width: 10),
          SizedBox(
              width: 76,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
          Expanded(child: _MiniStat(label: 'Min', value: min, unit: unit, decimals: decimals)),
          Expanded(child: _MiniStat(label: 'Avg', value: avg, unit: unit, decimals: decimals)),
          Expanded(child: _MiniStat(label: 'Max', value: max, unit: unit, decimals: decimals)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final double? value;
  final String unit;
  final int decimals;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.unit,
    required this.decimals,
  });

  @override
  Widget build(BuildContext context) {
    const valueStyle = TextStyle(
        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary);

    return Column(children: [
      // Recomputed stats slide to their new figure as history grows.
      value != null
          ? AnimatedNumber(
              value: value!,
              decimals: decimals,
              suffix: unit,
              style: valueStyle,
              textAlign: TextAlign.center,
            )
          : const Text('—', style: valueStyle),
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
    ]);
  }
}
