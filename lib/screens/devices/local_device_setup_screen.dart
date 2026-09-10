import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/local_esp32_service.dart';
import '../../widgets/connection_cpu_indicator.dart';
import '../../widgets/minimal_gif_header.dart';
import '../../widgets/fade_in.dart';

class LocalDeviceSetupScreen extends StatelessWidget {
  const LocalDeviceSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final esp32 = context.watch<LocalEsp32Service>();
    final connected = esp32.state == Esp32ConnectionState.connected;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeIn(
          child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            const MinimalGifHeader(title: 'Device Setup', subtitle: 'Connections'),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppShadows.card,
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    ConnectionCpuIndicator(state: esp32.state, size: 36),
                    const SizedBox(width: 12),
                    Text(connected ? 'Connected' : 'Not Connected',
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 18)),
                  ]),
                  const SizedBox(height: 16),
                  _InfoRow(label: 'Device address', value: esp32Ip, light: false),
                  _InfoRow(label: 'MAC address', value: esp32.macAddress ?? '—', light: false),
                  _InfoRow(
                    label: 'Last update',
                    value: esp32.lastUpdated != null
                        ? '${esp32.lastUpdated!.hour.toString().padLeft(2, '0')}:${esp32.lastUpdated!.minute.toString().padLeft(2, '0')}:${esp32.lastUpdated!.second.toString().padLeft(2, '0')}'
                        : '—',
                    light: connected,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text('HOW TO CONNECT', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final step in const [
                    '1|Power on your ESP32 - it broadcasts its own WiFi network directly',
                    '2|Open your phone\'s WiFi settings and join "$esp32ApSsidHint"',
                    '3|Come back to this app - it connects automatically once you\'re on that network',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(radius: 12, backgroundColor: AppColors.primary, child: Text(step.split('|')[0], style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 12),
                          Expanded(child: Text(step.split('|')[1], style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4))),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool light;
  const _InfoRow({required this.label, required this.value, required this.light});

  @override
  Widget build(BuildContext context) {
    final labelColor = light ? Colors.white70 : AppColors.textMuted;
    final valueColor = light ? Colors.white : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: labelColor, fontSize: 12)),
          Text(value, style: TextStyle(color: valueColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
