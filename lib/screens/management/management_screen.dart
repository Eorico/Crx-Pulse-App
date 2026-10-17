import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/sensor_icons.dart';
import '../../core/firmware_spec.dart';
import '../../services/local_esp32_service.dart';
import '../../widgets/sensor_card.dart';
import '../../widgets/feeding_section.dart';
import '../../widgets/minimal_gif_header.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/motion.dart';
import '../../widgets/sticky_header_delegate.dart';

/// Sensors + feeding.
///
/// Every safe-range test here comes from [FirmwareSpec] rather than a
/// literal typed into this file — the turbidity cut-off is the point
/// the firmware itself calls "Turbid", and the housing-temperature
/// cut-off is where the firmware's cooling fan is already at 100%.
class LocalManagementScreen extends StatelessWidget {
  const LocalManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final esp32 = context.watch<LocalEsp32Service>();

    final sensorCards = <Widget>[
      SensorCard(
        iconAsset: SensorIcons.ammonia,
        label: 'Ammonia',
        value: esp32.ammonia,
        unit: FirmwareSpec.ammoniaUnit,
        decimals: 2,
        isSafe: FirmwareSpec.ammoniaIsSafe,
        subtitle: esp32.ammonia == null
            ? null
            : FirmwareSpec.ammoniaStatusOf(esp32.ammonia!),
      ),
      SensorCard(
        iconAsset: SensorIcons.turbidity,
        label: 'Turbidity',
        value: esp32.turbidity,
        unit: '%',
        decimals: 1,
        isSafe: FirmwareSpec.turbidityIsSafe,
        subtitle: esp32.turbidityStatus,
      ),
      SensorCard(
        iconAsset: SensorIcons.ph,
        label: 'pH',
        value: esp32.ph,
        unit: '',
        decimals: 2,
        isSafe: FirmwareSpec.phIsSafe,
      ),
      SensorCard(
        iconAsset: SensorIcons.waterTemp,
        label: 'Water Temp',
        value: esp32.waterTempC,
        unit: '°C',
        decimals: 1,
        isSafe: FirmwareSpec.waterTempIsSafe,
      ),
      SensorCard(
        iconAsset: SensorIcons.housingTemp,
        label: 'Housing Temp',
        value: esp32.ambientTempC,
        unit: '°C',
        decimals: 1,
        isSafe: FirmwareSpec.housingTempIsSafe,
      ),
      SensorCard(
        iconAsset: SensorIcons.fan,
        label: 'Cooling Fan',
        value: esp32.fanActive ? esp32.fanDutyPercent.toDouble() : null,
        unit: '%',
        decimals: 0,
        isSafe: (_) => true,
        spinning: true,
      ),
    ];

    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: FadeIn(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => esp32.startPolling(),
            child: CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: StickyHeaderDelegate(
                    height: 76,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: MinimalGifHeader(title: 'Management', subtitle: 'Sensors and feeding'),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                  sliver: SliverList.list(children: [
                    // Collapses away rather than popping in and out as
                    // the connection comes and goes.
                    AnimatedSize(
                      duration: AppMotion.normal,
                      curve: AppMotion.smooth,
                      alignment: Alignment.topCenter,
                      child: (esp32.state != Esp32ConnectionState.connected &&
                              esp32.lastUpdated != null)
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: AppColors.textMuted.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(children: [
                                Icon(Icons.history_rounded, size: 15, color: AppColors.textSecondary),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Showing last known readings - not live',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ]),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const Text('SENSORS',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1)),
                    const SizedBox(height: 12),
                    // Tiles fan in one after another instead of the whole
                    // grid landing at once.
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.05,
                      children: FadeSlideIn.stagger(
                        sensorCards,
                        initialDelay: const Duration(milliseconds: 80),
                        from: const Offset(0, 0.12),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('FEEDING',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1)),
                    const SizedBox(height: 12),
                    const FadeSlideIn(
                      delay: Duration(milliseconds: 260),
                      child: LocalFeedingSection(),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
