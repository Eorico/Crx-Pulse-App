import 'package:crx_pulse/core/theme.dart';
import 'package:crx_pulse/widgets/notification_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  NotificationToastData data() => NotificationToastData(
        title: 'CRX-Pulse alert',
        message: 'pH is out of the safe range',
        timestamp: DateTime(2026, 11, 23, 9, 15),
        icon: LucideIcons.alertTriangle,
        accent: AppColors.warning,
        notificationId: 7,
      );

  testWidgets('card shows title, message and the full date and time',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationCard(data: data())),
    ));

    expect(find.text('CRX-Pulse alert'), findsOneWidget);
    expect(find.text('pH is out of the safe range'), findsOneWidget);
    expect(find.text('Nov 23, 2026 · 09:15 AM'), findsOneWidget);
  });

  testWidgets('tapping the card calls onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationCard(data: data(), onTap: () => tapped = true),
      ),
    ));

    await tester.tap(find.text('pH is out of the safe range'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
