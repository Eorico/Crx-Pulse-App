import 'package:crx_pulse/core/theme.dart';
import 'package:crx_pulse/widgets/notification_card.dart';
import 'package:crx_pulse/widgets/notification_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  NotificationToastData data() => NotificationToastData(
        title: 'CRX-Pulse alert',
        message: 'Ammonia level is too high',
        timestamp: DateTime(2026, 11, 24, 10, 42),
        icon: LucideIcons.alertTriangle,
        accent: AppColors.danger,
        notificationId: 3,
      );

  Future<SnackBar> showToast(WidgetTester tester, VoidCallback onTap) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  buildTopNotificationSnackBar(
                    context: context,
                    data: data(),
                    onTap: onTap,
                  ),
                ),
            child: const Text('show'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return tester.widget<SnackBar>(find.byType(SnackBar));
  }

  testWidgets('toast is floating with a top margin', (tester) async {
    final bar = await showToast(tester, () {});

    expect(bar.behavior, SnackBarBehavior.floating);
    expect(bar.margin, isNotNull);
    final margin = bar.margin!.resolve(TextDirection.ltr);
    expect(margin.top, greaterThan(0));
    expect(margin.bottom, 0);
  });

  testWidgets('tapping the toast calls onTap', (tester) async {
    var tapped = false;
    await showToast(tester, () => tapped = true);

    await tester.tap(find.text('Ammonia level is too high'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
