import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/device_provider.dart';
import '../../services/device_log_provider.dart';
import '../../services/local_esp32_service.dart';
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
  DeviceProvider? _devices;

  @override
  void initState() {
    super.initState();
    // Listen to DeviceProvider directly.
    //
    // This was the first bug: _syncStream() read the device id with
    // `context.read`, which registers NO dependency — so
    // didChangeDependencies never re-fired when the device row arrived,
    // and the postFrameCallback in initState had already run and found
    // null. DeviceProvider resolves its device over a Realtime stream,
    // so on a cold start it is routinely null when this screen mounts,
    // and the console then never started at all.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _devices = context.read<DeviceProvider>()..addListener(_syncStream);
      _syncStream();
    });
  }

  /// Open the log feed once a device is known, and re-open it if the
  /// paired device changes.
  void _syncStream() {
    if (!mounted) return;
    final deviceId = _devices?.deviceId;
    if (deviceId == null || deviceId == _streamingFor) return;
    _streamingFor = deviceId;
    context.read<DeviceLogProvider>().start(deviceId);
  }

  @override
  void dispose() {
    _devices?.removeListener(_syncStream);
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
    // Whether readings are arriving tells us the board is powered,
    // online and talking to Supabase — which is how we can tell "the
    // firmware is too old to mirror logs" apart from "the device is
    // simply off".
    final esp32 = context.watch<LocalEsp32Service>();

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

                    // Names whatever is actually blocking the console,
                    // instead of leaving an empty panel to be guessed at.
                    FadeSlideIn(
                      child: _LogFeedStatus(
                        logs: logs,
                        deviceId: deviceId,
                        deviceOnline: esp32.state == Esp32ConnectionState.connected,
                      ),
                    ),

                    // ── serial console ──
                    FadeSlideIn(
                      child: SerialConsole(
                        lines: logs.lines,
                        streaming: logs.isStreaming,
                        errorMessage: deviceId == null
                            ? 'Pair your ESP32 in the Setup tab to see its output.'
                            : logs.diagnosis?.summary,
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

/// Says why the console is empty.
///
/// Three independent things have to be true before a single line can
/// appear, and the failure of any one of them used to look identical: an
/// empty black panel. This works out which it is and says so, with the
/// fix.
class _LogFeedStatus extends StatelessWidget {
  final DeviceLogProvider logs;
  final String? deviceId;
  final bool deviceOnline;

  const _LogFeedStatus({
    required this.logs,
    required this.deviceId,
    required this.deviceOnline,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Nothing paired — the controls have no target.
    if (deviceId == null) {
      return const _StatusBanner(
        tone: _Tone.warn,
        icon: Icons.warning_amber_rounded,
        message: 'No device paired yet.',
        fix: 'Pair your ESP32 in the Setup tab to use these controls.',
      );
    }

    // 2. Still checking.
    if (logs.isProbing) {
      return const _StatusBanner(
        tone: _Tone.info,
        icon: Icons.sync_rounded,
        message: 'Checking the device log…',
      );
    }

    // 3. A real failure — most often the schema not having been re-run.
    final d = logs.diagnosis;
    if (d != null) {
      return _StatusBanner(
        tone: d.isSchemaProblem ? _Tone.error : _Tone.warn,
        icon: d.isSchemaProblem
            ? Icons.storage_rounded
            : Icons.error_outline_rounded,
        message: d.summary,
        fix: d.fix,
        detail: d.detail,
        onRetry: logs.retry,
      );
    }

    // 4. The table works but the device has never written to it. If
    //    readings ARE arriving, the board is online and talking to
    //    Supabase — so the only thing left is firmware too old to
    //    mirror its serial output.
    if (logs.tableReachable && !logs.hasEverReceived) {
      if (deviceOnline) {
        return const _StatusBanner(
          tone: _Tone.warn,
          icon: Icons.memory_rounded,
          message: 'The device is online and sending readings, but has never '
              'written a log line.',
          fix: 'Log mirroring was added in firmware v13.0.0 — flash '
              'hardware/crx_pulse_dev/crx_pulse to the ESP32.',
        );
      }
      return const _StatusBanner(
        tone: _Tone.info,
        icon: Icons.power_off_rounded,
        message: 'No log lines yet, and no readings are arriving either.',
        fix: 'Check the ESP32 is powered and on WiFi. Its log appears here '
            'once it reconnects.',
      );
    }

    // 5. Working.
    return _StatusBanner(
      tone: _Tone.ok,
      icon: Icons.check_circle_outline_rounded,
      message: logs.isStreaming
          ? 'Connected — streaming full serial output.'
          : 'Connected — showing recorded event lines.',
    );
  }
}

enum _Tone { ok, info, warn, error }

class _StatusBanner extends StatelessWidget {
  final _Tone tone;
  final IconData icon;
  final String message;
  final String? fix;

  /// The raw error, shown small — this is what makes a bug report
  /// actionable instead of "it doesn't work".
  final String? detail;
  final VoidCallback? onRetry;

  const _StatusBanner({
    required this.tone,
    required this.icon,
    required this.message,
    this.fix,
    this.detail,
    this.onRetry,
  });

  Color get _color => switch (tone) {
        _Tone.ok => AppColors.success,
        _Tone.info => AppColors.primary,
        _Tone.warn => AppColors.warning,
        _Tone.error => AppColors.danger,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: _color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message,
                    style: TextStyle(
                        color: _color == AppColors.success
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w700)),
                if (fix != null) ...[
                  const SizedBox(height: 4),
                  Text(fix!,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                          height: 1.4)),
                ],
                if (detail != null) ...[
                  const SizedBox(height: 6),
                  Text(detail!,
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontFamily: 'monospace',
                          height: 1.3)),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Try again'),
                    style: TextButton.styleFrom(
                      foregroundColor: _color,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
