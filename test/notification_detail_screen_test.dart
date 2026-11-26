import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:crx_pulse/core/sensor_icons.dart';
import 'package:crx_pulse/screens/notifications/notification_detail_screen.dart';
import 'package:crx_pulse/services/local_notification_provider.dart';

void main() {
  AppNotification alert({
    int id = 1,
    String message = 'Ammonia level is too high',
    String severity = 'warning',
    bool read = true,
  }) {
    return AppNotification(
      id: id,
      message: message,
      severity: severity,
      createdAt: DateTime(2026, 11, 24, 14, 5, 9),
      read: read,
    );
  }

  Future<void> pumpDetail(
      WidgetTester tester, AppNotification notification) async {
    await tester.pumpWidget(
      MaterialApp(home: NotificationDetailScreen(notification: notification)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ammonia alert shows the ammonia image and every detail',
      (tester) async {
    await pumpDetail(tester, alert());

    expect(find.image(const AssetImage(SensorIcons.ammonia)), findsOneWidget,
        reason: 'an ammonia alert must show the ammonia sensor image');
    expect(find.text('Ammonia level is too high'), findsOneWidget);
    expect(find.text('Ammonia Sensor'), findsWidgets);
    expect(find.text('Warning'), findsWidgets);
    expect(find.text('2026-11-24'), findsOneWidget);
    expect(find.text('14:05:09'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
  });

  testWidgets('each sensor alert uses its own image', (tester) async {
    final cases = <String, String>{
      'pH is out of the safe range': SensorIcons.ph,
      'Water turbidity is too high': SensorIcons.turbidity,
      'Water temperature is out of range': SensorIcons.waterTemp,
      'Housing temperature is high — cooling fan at full speed':
          SensorIcons.housingTemp,
    };

    for (final entry in cases.entries) {
      await pumpDetail(tester, alert(message: entry.key));
      expect(find.image(AssetImage(entry.value)), findsOneWidget,
          reason: '${entry.key} should use ${entry.value}');
    }
  });

  testWidgets('unrecognised alerts fall back to the bell image',
      (tester) async {
    await pumpDetail(tester, alert(message: 'Unexpected system event'));
    expect(find.image(const AssetImage(SensorIcons.bell)), findsOneWidget);
  });

  testWidgets('unread status is shown on the detail page', (tester) async {
    await pumpDetail(tester, alert(read: false));
    expect(find.text('Unread'), findsOneWidget);
  });

  testWidgets('back button leaves the detail page', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NotificationDetailScreen(notification: alert()),
              ),
            ),
            child: const Text('open detail'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open detail'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationDetailScreen), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.chevronLeft));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationDetailScreen), findsNothing);
  });
}
