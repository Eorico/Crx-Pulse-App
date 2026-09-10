import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/sensor_icons.dart';
import '../../services/local_esp32_service.dart';
import '../../widgets/thermal_fan_widget.dart';
import '../../widgets/connection_cpu_indicator.dart';
import '../../widgets/spinning_image.dart';
import '../../widgets/fade_in.dart';

/// Dashboard tab - a fuller overview of everything being monitored,
/// not just a handful of cards. Water level removed (no sensor for
/// it). Lives inside MainTabScaffold's IndexedStack now - no Scaffold
/// or drawer of its own, the floating bottom nav handles navigation.
class LocalHomeScreen extends StatelessWidget {
  const LocalHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final esp32 = context.watch<LocalEsp32Service>();

    return Container(
      color: AppColors.background,
      child: Stack(
        children: [
          SafeArea(
            child: FadeIn(
              child: RefreshIndicator(
                onRefresh: () async => esp32.startPolling(),
                child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Dashboard', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.5)),
                          Text('Live pond overview', style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      ConnectionCpuIndicator(state: esp32.state),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── SYSTEM STATUS - bold hero card, Nike-style block ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(28)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Wave when connected, "no connection" mascot
                        // otherwise - "connecting" is treated the
                        // same as not-yet-connected here, matching
                        // the same binary treatment as the CPU
                        // indicator elsewhere in the app.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            esp32.state == Esp32ConnectionState.connected
                                ? 'assets/images/mascot/wave-anim.gif'
                                : 'assets/images/mascot/no-connection-anim.gif',
                            key: ValueKey(esp32.state == Esp32ConnectionState.connected),
                            width: 84, height: 84, fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('STATUS', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2)),
                              const SizedBox(height: 6),
                              Text(
                                esp32.state == Esp32ConnectionState.connected ? 'All Systems Go' : 'Standing By',
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                              ),
                              const SizedBox(height: 12),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                SpinningImage(asset: SensorIcons.fan, size: 18, spinning: esp32.fanActive),
                                const SizedBox(width: 8),
                                Flexible(child: Text(esp32.fanActive ? 'Cooling active · ${esp32.fanDutyPercent}%' : 'Cooling idle', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const _SectionLabel(title: 'Water Quality'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.25,
                    children: [
                      _StatCard(iconAsset: SensorIcons.ph, label: 'pH Level', value: esp32.ph, unit: '', decimals: 1),
                      _StatCard(iconAsset: SensorIcons.ammonia, label: 'Ammonia', value: esp32.ammonia, unit: ' ppm', decimals: 2),
                      _StatCard(iconAsset: SensorIcons.turbidity, label: 'Turbidity', value: esp32.turbidity, unit: ' NTU', decimals: 1),
                      _StatCard(iconAsset: SensorIcons.waterTemp, label: 'Water Temp', value: esp32.waterTempC, unit: '°C', decimals: 1),
                    ],
                  ),

                  const SizedBox(height: 8),
                  const _SectionLabel(title: 'Environment'),
                  _StatCard(iconAsset: SensorIcons.housingTemp, label: 'Housing Temperature', value: esp32.ambientTempC, unit: '°C', decimals: 1, wide: true),

                  if (esp32.lastUpdated != null) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        'Updated ${esp32.lastUpdated!.hour.toString().padLeft(2, '0')}:${esp32.lastUpdated!.minute.toString().padLeft(2, '0')}:${esp32.lastUpdated!.second.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          ),
          ThermalFanWidget(
            waterTempC: esp32.waterTempC,
            ambientTempC: esp32.ambientTempC,
            isLive: esp32.state == Esp32ConnectionState.connected,
            fanActive: esp32.fanActive,
            fanDutyPercent: esp32.fanDutyPercent,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 8),
      child: Text(title.toUpperCase(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
    );
  }
}


class _StatCard extends StatelessWidget {
  final String iconAsset;
  final String label;
  final double? value;
  final String unit;
  final int decimals;
  final bool wide;
  const _StatCard({required this.iconAsset, required this.label, required this.value, required this.unit, required this.decimals, this.wide = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
      child: wide
          ? Row(children: [
              Image.asset(iconAsset, width: 36, height: 36),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600))),
              Text(value != null ? '${value!.toStringAsFixed(decimals)}$unit' : '—', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Image.asset(iconAsset, width: 32, height: 32),
                const Spacer(),
                Text(
                  value != null ? '${value!.toStringAsFixed(decimals)}$unit' : 'N/A',
                  style: TextStyle(fontSize: value != null ? 22 : 14, fontWeight: FontWeight.w800, color: value != null ? AppColors.textPrimary : AppColors.textMuted),
                ),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
    );
  }
}
