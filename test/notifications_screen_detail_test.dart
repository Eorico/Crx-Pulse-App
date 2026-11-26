import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:crx_pulse/core/sensor_icons.dart';
import 'package:crx_pulse/screens/notifications/notifications_screen.dart';
import 'package:crx_pulse/screens/notifications/notification_detail_screen.dart';
import 'package:crx_pulse/services/local_notification_provider.dart';

/// Avoids LocalDb/sqflite in widget tests while preserving the provider's
/// real notification list and read-state behaviour.
class FakeNotificationProvider extends LocalNotificationProvider {
  final List<AppNotification> initial;
  int markCalls = 0;

  FakeNotificationProvider(this.initial);

  @override
  Future<void> fetchNotifications() async {
    notifications = List.of(initial);
    notifyListeners();
  }

  @override
  Future<void> markAsRead(int id) async {
    markCalls++;
    notifications = notifications
        .map((n) => n.id == id
            ? AppNotification(
                id: n.id,
                message: n.message,
                severity: n.severity,
                createdAt: n.createdAt,
                read: true,
              )
            : n)
        .toList();
    notifyListeners();
  }
}

/// Simulates a contended SQLite write. Navigation must not wait on this:
/// the old implementation awaited markAsRead before pushing the route,
/// so the row turned white but the detail page never appeared.
class HangingNotificationProvider extends FakeNotificationProvider {
  HangingNotificationProvider(super.initial);

  @override
  Future<void> markAsRead(int id) {
    markCalls++;
    return Completer<void>().future;
  }
}

void main() {
  AppNotification alert(int id, String message) => AppNotification(
        id: id,
        message: message,
        severity: 'warning',
        createdAt: DateTime(2026, 11, 24, 9, 30),
        // Read rows have no repeating pulse animation, so the widget
        // test can settle. markCalls still proves the tap marks as read.
        read: true,
      );

  testWidgets(
      'tapping an ammonia alert opens its detail page and marks it read',
      (tester) async {
    final provider = FakeNotificationProvider([
      alert(1, 'Ammonia level is too high'),
      alert(2, 'pH is out of the safe range'),
    ]);

    await tester.pumpWidget(
      ChangeNotifierProvider<LocalNotificationProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Material(child: LocalNotificationsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The shared notification card keeps the full message tappable.
    expect(find.text('Ammonia level is too high'), findsOneWidget);

    await tester.tap(find.text('Ammonia level is too high'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationDetailScreen), findsOneWidget);
    expect(
        find.descendant(
          of: find.byType(NotificationDetailScreen),
          matching: find.image(const AssetImage(SensorIcons.ammonia)),
        ),
        findsOneWidget,
        reason: 'the opened detail page must show the ammonia image');
    expect(find.text('Ammonia level is too high'), findsOneWidget);
    expect(provider.markCalls, 1);
    expect(provider.notifications.first.read, isTrue);
    expect(find.text('Read'), findsWidgets);
  });

  testWidgets('tapping a pH alert opens the pH detail page', (tester) async {
    final provider = FakeNotificationProvider([
      alert(3, 'pH is out of the safe range'),
    ]);

    await tester.pumpWidget(
      ChangeNotifierProvider<LocalNotificationProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Material(child: LocalNotificationsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('pH is out of the safe range'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationDetailScreen), findsOneWidget);
    expect(
        find.descendant(
          of: find.byType(NotificationDetailScreen),
          matching: find.image(const AssetImage(SensorIcons.ph)),
        ),
        findsOneWidget);
  });

  testWidgets('detail page opens even while marking as read is still pending',
      (tester) async {
    final provider = HangingNotificationProvider([
      alert(4, 'Ammonia level is too high'),
    ]);

    await tester.pumpWidget(
      ChangeNotifierProvider<LocalNotificationProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Material(child: LocalNotificationsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ammonia level is too high'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationDetailScreen), findsOneWidget,
        reason: 'the tap must open the page without waiting on the database');
    expect(
        find.descendant(
          of: find.byType(NotificationDetailScreen),
          matching: find.image(const AssetImage(SensorIcons.ammonia)),
        ),
        findsOneWidget);
    expect(provider.markCalls, 1);
  });
}
