import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'home/home_screen.dart';
import 'management/management_screen.dart';
import 'devices/device_setup_screen.dart';
import 'notifications/notifications_screen.dart';
import 'analytics/analytics_screen.dart';
import 'profile/profile_screen.dart';
import 'settings/settings_screen.dart';
import '../widgets/tab_nav.dart';
import '../widgets/motion.dart';
import '../widgets/notification_card.dart';
import '../widgets/notification_toast.dart';
import '../widgets/thermal_fan_widget.dart';
import '../core/theme.dart';
import '../services/device_provider.dart';
import '../services/local_esp32_service.dart';
import '../services/local_feeding_provider.dart';
import '../services/local_notification_provider.dart';
import '../services/local_analytics_provider.dart';
import '../services/realtime_sync_service.dart';

/// PageView-based rather than IndexedStack — swiping left/right moves
/// between tabs with the same natural sliding motion as a Facebook-style
/// tab bar, and the bottom nav stays synced with whichever page is
/// showing, whether you got there by swiping OR tapping a tab icon.
/// Live sensor state is not held by the pages themselves — it lives in
/// the app-wide providers — so a page being rebuilt when you come back
/// to it costs nothing.
///
/// Pages also parallax slightly as they slide: the incoming page eases
/// up to full scale and opacity, which gives the swipe a sense of depth
/// instead of two flat panels sliding past each other.
///
/// This widget is also where feeding-schedule and notification-threshold
/// checks run on every sensor update, and where every connection failure
/// and new alert becomes a toast — one place making that decision,
/// regardless of which tab is visible.
class MainTabScaffold extends StatefulWidget {
  const MainTabScaffold({super.key});

  @override
  State<MainTabScaffold> createState() => _MainTabScaffoldState();
}

class _MainTabScaffoldState extends State<MainTabScaffold> {
  int _index = 0;
  late final PageController _pageController = PageController(initialPage: 0);
  final RealtimeSyncService _realtimeSync = RealtimeSyncService();
  Esp32ConnectionState? _lastEsp32State;
  bool? _lastOfflineDirect;

  // A stored alert must not pop up just because the app opened. Suppress
  // toasts until the first fetch has established the id baseline, and detect
  // new rows by id rather than list length (SQLite caps the history at 100).
  bool _notificationsReady = false;
  int _maxNotificationId = 0;

  static const _screens = [
    LocalHomeScreen(),
    LocalManagementScreen(),
    LocalAnalyticsScreen(),
    LocalDeviceSetupScreen(),
    LocalNotificationsScreen(),
    LocalProfileScreen(),
    LocalSettingsScreen(),
  ];

  void _onTabTap(int i) {
    if (i == _index) return;
    // animateToPage gives the same smooth sliding motion as a manual
    // swipe would - tapping a tab and swiping to it look and feel
    // identical, matching real Facebook-style tab behavior.
    _pageController.animateToPage(
      i,
      duration: AppMotion.normal,
      curve: AppMotion.enter,
    );
  }

  void _onPageChanged(int i) {
    // Fires for BOTH a manual swipe and animateToPage completing -
    // this is the single source of truth that keeps the bottom nav's
    // highlighted icon in sync with whatever's actually on screen.
    setState(() => _index = i);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The fetch below already covers the current transport. Seed the
      // transition tracker so the first update does not duplicate it.
      _lastOfflineDirect = context.read<LocalEsp32Service>().isOfflineDirect;
      context.read<LocalFeedingProvider>().fetchSchedules();
      context.read<LocalNotificationProvider>().fetchNotifications().then((_) {
        if (!mounted) return;
        final rows = context.read<LocalNotificationProvider>().notifications;
        for (final row in rows) {
          if (row.id > _maxNotificationId) _maxNotificationId = row.id;
        }
        _notificationsReady = true;
      });
      context.read<LocalEsp32Service>().addListener(_onEsp32Update);
      context.read<LocalNotificationProvider>().addListener(_onNotificationsUpdate);
      context.read<LocalEsp32Service>().startPolling();
    });
  }

  void _onEsp32Update() {
    final esp32 = context.read<LocalEsp32Service>();
    final feeding = context.read<LocalFeedingProvider>();

    // The first AP reading arrives after this screen's initial fetch, and
    // the Supabase stream is useless while offline. Reload schedules on
    // both transitions so the list always matches the live transport.
    if (_lastOfflineDirect != esp32.isOfflineDirect) {
      _lastOfflineDirect = esp32.isOfflineDirect;
      unawaited(feeding.fetchSchedules());
    }
    // An offline cold start has no paired id in Supabase. The board
    // reported one in its validated reading, so let the UI use it for
    // feeds, schedules and component tests. A paired id always wins.
    if (esp32.isOfflineDirect && esp32.apDeviceId != null) {
      context.read<DeviceProvider>().adoptOfflineDeviceId(esp32.apDeviceId!);
    }

    feeding.checkDueSchedules(esp32);
    context.read<LocalNotificationProvider>().checkThresholds(esp32);
    context.read<LocalAnalyticsProvider>().maybeLogReading(esp32);
    _realtimeSync.pushCurrentReading(esp32);

    if (_lastEsp32State != null && _lastEsp32State != esp32.state) {
      if (esp32.state == Esp32ConnectionState.unreachable) {
        _showToast(NotificationToastData(
          title: 'Device connection',
          message: esp32.errorMessage ?? "Can't reach the device.",
          timestamp: DateTime.now(),
          icon: LucideIcons.wifiOff,
          accent: AppColors.danger,
        ));
      } else if (esp32.state == Esp32ConnectionState.connected &&
          _lastEsp32State == Esp32ConnectionState.unreachable) {
        _showToast(NotificationToastData(
          title: 'Device connection',
          message: 'Reconnected to device',
          timestamp: DateTime.now(),
          icon: LucideIcons.wifi,
          accent: AppColors.success,
        ));
      }
    }
    _lastEsp32State = esp32.state;
  }

  void _onNotificationsUpdate() {
    if (!_notificationsReady) return;
    final provider = context.read<LocalNotificationProvider>();
    final notifications = provider.notifications;
    // Ordered newest first; anything above the baseline arrived since the
    // app opened (or since the last toast), even when history is full.
    final fresh = notifications.where((n) => n.id > _maxNotificationId).toList();
    if (fresh.isEmpty) return;
    for (final row in fresh) {
      if (row.id > _maxNotificationId) _maxNotificationId = row.id;
    }
    final alert = fresh.first;
    _showToast(
        NotificationToastData(
          title: 'CRX-Pulse alert',
          message: alert.message,
          timestamp: alert.createdAt,
          icon: LucideIcons.alertTriangle,
          accent: alert.severity == 'warning' ? AppColors.warning : AppColors.danger,
          notificationId: alert.id,
        ),
        onTap: () {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          provider.markAsRead(alert.id);
          _onTabTap(4);
        },
      );
  }

  void _showToast(NotificationToastData data, {VoidCallback? onTap}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      buildTopNotificationSnackBar(context: context, data: data, onTap: onTap),
    );
  }

  @override
  void dispose() {
    context.read<LocalEsp32Service>().removeListener(_onEsp32Update);
    context.read<LocalNotificationProvider>().removeListener(_onNotificationsUpdate);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esp32 = context.watch<LocalEsp32Service>();
    const screens = _screens;

    return Scaffold(
      extendBody: true,
      // Stack keeps ThermalFanWidget floating over WHICHEVER page is
      // currently showing in the PageView beneath it - one shared
      // instance across all 7 tabs (not per-screen), so its draggable
      // position and expand/collapse state persist identically no
      // matter which tab you're on. Per the explicit requirement:
      // visible everywhere authenticated, never on the Login/Register/
      // Forgot Password screens (which live entirely outside
      // MainTabScaffold, so this can't reach them anyway).
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: screens.length,
            itemBuilder: (context, i) => _ParallaxPage(
              controller: _pageController,
              index: i,
              child: screens[i],
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
      bottomNavigationBar: TabNav(currentIndex: _index, onTap: _onTabTap),
    );
  }
}

/// Scales and fades a page by how far it is from centre, so a swipe
/// reads as pages moving in depth rather than sliding flat.
///
/// The child widget instance is captured, not rebuilt, so only the
/// Transform/Opacity around it are recomputed as you scroll — the page
/// subtree underneath is untouched, and lifetimes are exactly what
/// PageView gave before.
class _ParallaxPage extends StatelessWidget {
  final PageController controller;
  final int index;
  final Widget child;

  const _ParallaxPage({
    required this.controller,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Distance from this page's centre, 0 when centred, 1 when a
        // full page away. Before the first layout `page` is null, so
        // fall back to the initial page.
        final page = controller.hasClients && controller.position.haveDimensions
            ? (controller.page ?? controller.initialPage.toDouble())
            : controller.initialPage.toDouble();
        final delta = (page - index).abs().clamp(0.0, 1.0);

        return Transform.scale(
          scale: 1 - 0.06 * delta,
          child: Opacity(opacity: 1 - 0.35 * delta, child: child),
        );
      },
    );
  }
}
