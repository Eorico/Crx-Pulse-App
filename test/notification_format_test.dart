import 'package:flutter_test/flutter_test.dart';
import 'package:crx_pulse/core/notification_format.dart';

void main() {
  group('formatNotificationTime', () {
    test('an older date shows month, day, year and the time', () {
      expect(
        formatNotificationTime(DateTime(2026, 11, 23, 9, 15)),
        'Nov 23, 2026 · 09:15 AM',
      );
    });

    test("today's date is labelled Today", () {
      final now = DateTime.now();
      expect(
        formatNotificationTime(DateTime(now.year, now.month, now.day, 14, 5)),
        startsWith('Today '),
      );
    });

    test('noon and midnight keep their 12-hour names', () {
      expect(formatNotificationTime(DateTime(2026, 11, 23, 12, 0)),
          endsWith('12:00 PM'));
      expect(formatNotificationTime(DateTime(2026, 11, 23, 0, 0)),
          endsWith('12:00 AM'));
    });
  });
}
