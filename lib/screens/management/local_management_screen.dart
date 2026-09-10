import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/sensor_icons.dart';
import '../../services/local_esp32_service.dart';
import '../../widgets/sensor_card.dart';
import '../../widgets/local_feeding_section.dart';
import '../../widgets/minimal_gif_header.dart';
import '../../widgets/fade_in.dart';

class LocalManagementScreen extends StatelessWidget {
  const LocalManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final esp32 = context.watch<LocalEsp32Service>();

    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: FadeIn(
          child: RefreshIndicator(
            onRefresh: () async => esp32.startPolling(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              children: [
                const MinimalGifHeader(title: 'Management', subtitle: 'Sensors and feeding'),
                const SizedBox(height: 20),

                const Text('SENSORS', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.1,
                  children: [
                    SensorCard(iconAsset: SensorIcons.ph, label: 'pH', value: esp32.ph, unit: '', decimals: 1, isSafe: (v) => v >= 6.5 && v <= 8.5),
                    SensorCard(iconAsset: SensorIcons.ammonia, label: 'Ammonia', value: esp32.ammonia, unit: '', decimals: 2, isSafe: (v) => v < 0.5),
                    SensorCard(iconAsset: SensorIcons.turbidity, label: 'Turbidity', value: esp32.turbidity, unit: '', decimals: 1, isSafe: (v) => v < 50),
                    SensorCard(iconAsset: SensorIcons.waterTemp, label: 'Water temp', value: esp32.waterTempC, unit: '°', decimals: 1, isSafe: (v) => v >= 20 && v <= 30),
                    SensorCard(iconAsset: SensorIcons.housingTemp, label: 'Housing temp', value: esp32.ambientTempC, unit: '°', decimals: 1, isSafe: (v) => v < 34),
                    SensorCard(iconAsset: SensorIcons.fan, label: 'Fan', value: esp32.fanActive ? esp32.fanDutyPercent.toDouble() : null, unit: '%', decimals: 0, isSafe: (_) => true, spinning: true),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('FEEDING', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
                const SizedBox(height: 12),
                const LocalFeedingSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
