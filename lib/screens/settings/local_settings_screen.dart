import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/device_provider.dart';
import '../../services/device_log_provider.dart';
import '../../widgets/minimal_gif_header.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/motion.dart';
import '../../widgets/serial_console.dart';
import '../../widgets/component_test_panel.dart';
import '../../widgets/sticky_header_delegate.dart';

/// Settings — now TEST COMPONENTS plus Log Out.
///
/// The old Profile and Device Setup rows are gone: both are already
/// tabs in the bottom nav, so these were a second route to the same two
/// screens — and they were wired with `onTap: null`, so they did
/// nothing at all.
///
/// In their place: a live view of the ESP32's serial output, and direct
/// controls for the feeder servo and the DC rotator.
///
/// On the serial console — the phone has NO serial or USB link to the
/// ESP32. It reaches the device only through Supabase. So the firmware
/// mirrors every line it prints into the `device_logs` table and this
/// subscribes to it; the text here is the same text a serial monitor
/// shows. Verbose output (the sensor block, every 2 s) only flows while
/// this screen is open — see [DeviceLogProvider].
class LocalSettingsScreen extends StatefulWidget {
  const LocalSettingsScreen({super.key});

  @override
  State<LocalSettingsScreen> createState() => _LocalSettingsScreenState();
}

class _LocalSettingsScreenState extends State<LocalSettingsScreen> {
  String? _streamingFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncStream());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncStream();
  }

  /// Open the log feed once a device is known, and re-open it if the
  /// paired device changes. Pairing can finish after this screen is
  /// first built, so this cannot be a one-shot in initState.
  void _syncStream() {
    if (!mounted) return;
    final deviceId = context.read<DeviceProvider>().deviceId;
    if (deviceId == null || deviceId == _streamingFor) return;
    _streamingFor = deviceId;
    context.read<DeviceLogProvider>().start(deviceId);
  }

  @override
  void dispose() {
    // Tell the device to stop mirroring verbose output now rather than
    // waiting for its deadline to lapse. read() is safe here because
    // the provider lives above this widget, at the app root.
    context.read<DeviceLogProvider>().stop();
    super.dispose();
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // The _AuthGate StreamBuilder in main.dart reacts to this
      // automatically - once signed out, it swaps straight back to
      // LoginScreen with no manual navigation needed here.
      await AuthService().signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<DeviceLogProvider>();
    final deviceId = context.watch<DeviceProvider>().deviceId;

    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: FadeIn(
          child: CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: StickyHeaderDelegate(
                  height: 76,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: MinimalGifHeader(
                        title: 'Settings', subtitle: 'Test components'),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                sliver: SliverList.list(
                  children: [
                    const _SectionLabel('TEST COMPONENTS'),

                    if (deviceId == null)
                      const FadeSlideIn(child: _NoDeviceWarning())
                    else
                      const SizedBox.shrink(),

                    // ── serial console ──
                    FadeSlideIn(
                      child: SerialConsole(
                        lines: logs.lines,
                        streaming: logs.isStreaming,
                        errorMessage: deviceId == null
                            ? 'Pair your ESP32 in Device Setup to see its output.'
                            : logs.errorMessage,
                        onClear: deviceId == null ? null : logs.clear,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Live output from the device. Event lines are always '
                      'recorded; the full sensor block streams only while this '
                      'screen is open.',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11, height: 1.35),
                    ),

                    const SizedBox(height: 20),
                    const _SectionLabel('CONTROLS'),
                    ComponentTestPanel(deviceId: deviceId),

                    const SizedBox(height: 32),
                    const _SectionLabel('ACCOUNT'),
                    FadeSlideIn(
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmLogout(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            animationDuration: AppMotion.fast,
                          ),
                          icon: const Icon(LucideIcons.logOut, size: 18),
                          label: const Text('Log Out',
                              style:
                                  TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
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

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(title,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1)),
    );
  }
}

class _NoDeviceWarning extends StatelessWidget {
  const _NoDeviceWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12)),
      child: const Row(children: [
        Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
        SizedBox(width: 8),
        Expanded(
            child: Text(
                'No device paired yet. Pair your ESP32 in the Setup tab to use '
                'these controls.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12, height: 1.3))),
      ]),
    );
  }
}
