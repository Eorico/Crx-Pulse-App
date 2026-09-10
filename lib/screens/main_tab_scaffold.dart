import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'home/local_home_screen.dart';
import 'management/local_management_screen.dart';
import 'devices/local_device_setup_screen.dart';
import 'notifications/local_notifications_screen.dart';
import 'analytics/local_analytics_screen.dart';
import '../widgets/floating_bottom_nav.dart';
import '../core/theme.dart';
import '../services/local_esp32_service.dart';
import '../services/local_feeding_provider.dart';
import '../services/local_notification_provider.dart';
import '../services/local_analytics_provider.dart';

/// Replaces the sidebar entirely - IndexedStack keeps all 4 screens
/// alive simultaneously (so LocalEsp32Service's polling and each
/// screen's own state survive switching tabs, rather than restarting
/// every time), with the floating pill nav overlaid on top.
///
/// This widget also drives the feeding-schedule and notification-
/// threshold checks on every sensor update, regardless of which tab
/// is currently visible - it's the one place that's always alive for
/// the whole session. It's also where every connection failure and
/// new alert becomes a toast, instead of a persistent inline banner
/// on each screen - one single place decides when to interrupt the
/// user, rather than every screen doing its own thing.
class MainTabScaffold extends StatefulWidget {
  const MainTabScaffold({super.key});

  @override
  State<MainTabScaffold> createState() => _MainTabScaffoldState();
}

class _MainTabScaffoldState extends State<MainTabScaffold> with SingleTickerProviderStateMixin {
  int _index = 0;
  Esp32ConnectionState? _lastEsp32State;
  int _lastNotificationCount = 0;

  // Drives a fade that replays on EVERY tab switch, not just once on
  // launch - separate from IndexedStack, which still keeps all 4
  // screens alive underneath so polling/state never restarts. Only
  // the visual transition replays; the actual screen state doesn't.
  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..value = 1.0;

  static const _screens = [
    LocalHomeScreen(),
    LocalManagementScreen(),
    LocalAnalyticsScreen(),
    LocalDeviceSetupScreen(),
    LocalNotificationsScreen(),
  ];

  void _onTabTap(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _fadeController.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocalFeedingProvider>().fetchSchedules();
      context.read<LocalNotificationProvider>().fetchNotifications().then((_) {
        _lastNotificationCount = context.read<LocalNotificationProvider>().notifications.length;
      });
      context.read<LocalEsp32Service>().addListener(_onEsp32Update);
      context.read<LocalNotificationProvider>().addListener(_onNotificationsUpdate);
      context.read<LocalEsp32Service>().startPolling();
    });
  }

  void _onEsp32Update() {
    final esp32 = context.read<LocalEsp32Service>();
    context.read<LocalFeedingProvider>().checkDueSchedules(esp32);
    context.read<LocalNotificationProvider>().checkThresholds(esp32);
    context.read<LocalAnalyticsProvider>().maybeLogReading(esp32);

    // Toast on genuine STATE TRANSITIONS only, not every poll - a
    // banner that reappeared every 3 seconds would be far more
    // annoying than helpful.
    if (_lastEsp32State != null && _lastEsp32State != esp32.state) {
      if (esp32.state == Esp32ConnectionState.unreachable) {
        _showToast(esp32.errorMessage ?? "Can't reach the device.", isError: true);
      } else if (esp32.state == Esp32ConnectionState.connected && _lastEsp32State == Esp32ConnectionState.unreachable) {
        _showToast('Reconnected to device', isError: false);
      }
    }
    _lastEsp32State = esp32.state;
  }

  void _onNotificationsUpdate() {
    final notifications = context.read<LocalNotificationProvider>().notifications;
    if (notifications.length > _lastNotificationCount && notifications.isNotEmpty) {
      _showToast(notifications.first.message, isError: true, icon: LucideIcons.alertTriangle);
    }
    _lastNotificationCount = notifications.length;
  }

  void _showToast(String message, {required bool isError, IconData icon = LucideIcons.wifiOff}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(icon, color: isError ? AppColors.danger : AppColors.success, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ]),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    context.read<LocalEsp32Service>().removeListener(_onEsp32Update);
    context.read<LocalNotificationProvider>().removeListener(_onNotificationsUpdate);
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
        child: IndexedStack(index: _index, children: _screens),
      ),
      bottomNavigationBar: FloatingBottomNav(currentIndex: _index, onTap: _onTabTap),
    );
  }
}
