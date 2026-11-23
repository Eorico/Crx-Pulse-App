import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/local_esp32_service.dart';
import '../../services/device_provider.dart';
import '../../widgets/connection_cpu_indicator.dart';
import '../../widgets/firmware_build_row.dart';
import '../../widgets/minimal_gif_header.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/motion.dart';
import '../../widgets/sticky_header_delegate.dart';

/// Device Setup, for the Supabase architecture. The ESP32 joins your WiFi
/// router and writes straight to Supabase, so this screen's job is
/// PAIRING: claim a device_id for your account (a row in `devices`). There
/// is no secret key to copy — the firmware already carries the Supabase
/// anon key; you only set DEVICE_ID in the firmware to match. Live status
/// comes from whether fresh readings are arriving in the readings table.
class LocalDeviceSetupScreen extends StatefulWidget {
  const LocalDeviceSetupScreen({super.key});

  @override
  State<LocalDeviceSetupScreen> createState() => _LocalDeviceSetupScreenState();
}

class _LocalDeviceSetupScreenState extends State<LocalDeviceSetupScreen> {
  final _idController = TextEditingController(text: 'tank_01');
  final _nameController = TextEditingController(text: 'My Tank');

  Future<void> _pair() async {
    final device = context.read<DeviceProvider>();
    final id = _idController.text.trim();
    if (id.isEmpty) return;
    try {
      await device.pairDevice(id, name: _nameController.text);
      if (!mounted) return;
      // Re-attempt live tracking now that a device is paired.
      context.read<LocalEsp32Service>().startPolling();
      _showPairedDialog(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pairing failed: $e')));
    }
  }

  void _showPairedDialog(String id) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Device paired'),
        content: Text(
          'Device "$id" is now linked to your account.\n\n'
          'In the firmware, set:\n'
          '    DEVICE_ID = "$id"\n\n'
          'The Supabase URL and key are already compiled into the firmware, '
          'so there is nothing else to copy. Flash the ESP32 and its readings '
          'will appear here live.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esp32 = context.watch<LocalEsp32Service>();
    final device = context.watch<DeviceProvider>();
    final connected = esp32.state == Esp32ConnectionState.connected;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeIn(
          child: CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: StickyHeaderDelegate(
                  height: 76,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: MinimalGifHeader(title: 'Device Setup', subtitle: 'Pair your ESP32'),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                sliver: SliverList.list(children: FadeSlideIn.stagger([
                  const SizedBox(height: 12),

                  // Live status card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card, border: Border.all(color: AppColors.border)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          ConnectionCpuIndicator(state: esp32.state, size: 36),
                          const SizedBox(width: 12),
                          // Cross-fades when the device comes and goes.
                          SwapIn(
                            swapKey: connected,
                            child: Text(connected ? 'Receiving data' : 'No live data',
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18)),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        _InfoRow(label: 'Paired device', value: device.deviceName ?? device.deviceId ?? 'None yet'),
                        _InfoRow(
                          label: 'Last reading',
                          value: esp32.lastUpdated != null
                              ? '${esp32.lastUpdated!.hour.toString().padLeft(2, '0')}:${esp32.lastUpdated!.minute.toString().padLeft(2, '0')}:${esp32.lastUpdated!.second.toString().padLeft(2, '0')}'
                              : '—',
                        ),
                        FirmwareBuildRow(tag: esp32.firmwareBuildTag),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text('PAIR A DEVICE', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Device ID', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(controller: _idController, decoration: const InputDecoration(hintText: 'tank_01')),
                        const SizedBox(height: 14),
                        const Text('Name', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(controller: _nameController, decoration: const InputDecoration(hintText: 'My Tank')),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: device.loading ? null : _pair,
                            icon: device.loading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.link_rounded, size: 18),
                            // There is no key to re-issue in the
                            // Supabase build — pairing is just a row in
                            // `devices` claiming this id, so the old
                            // "(new key)" wording promised something
                            // that does not happen.
                            label: Text(device.hasDevice ? 'Re-pair Device' : 'Pair Device'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text('HOW IT WORKS', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final step in const [
                          '1|Tap Pair Device to link this Device ID to your account',
                          '2|In the firmware set the same DEVICE_ID, then flash the ESP32 (the Supabase URL + key are already built in)',
                          '3|The ESP32 joins your WiFi router and writes readings to Supabase — they appear here live',
                        ])
                          FadeSlideIn(
                            // Steps count themselves in, one per beat.
                            delay: Duration(
                                milliseconds: 420 + 90 * (int.parse(step.split('|')[0]) - 1)),
                            from: const Offset(-0.06, 0),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                      radius: 12,
                                      backgroundColor: AppColors.primary,
                                      child: Text(step.split('|')[0],
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Text(step.split('|')[1],
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 13,
                                              height: 1.4))),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ])),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
