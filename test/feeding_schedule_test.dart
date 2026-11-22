import 'package:flutter_test/flutter_test.dart';
import 'package:crx_pulse/core/feeding_schedule.dart';
import 'package:crx_pulse/services/local_feeding_provider.dart';

void main() {
  FeedingSchedule feed(String id, String time, {String? feedDate}) =>
      FeedingSchedule(
        id: id,
        time: time,
        grams: 10,
        rotatorPwm: 255,
        active: true,
        feedDate: feedDate,
      );

  FeedingDraft draft(String time, {String? feedDate}) => FeedingDraft(
        feedDate: feedDate,
        time: time,
        grams: 10,
        rotatorPwm: 255,
      );

  group('deviceTodayDate', () {
    test('uses the device UTC+8 day, not the phone local day', () {
      expect(
        deviceTodayDate(now: DateTime.utc(2026, 10, 22, 16, 30)),
        '2026-10-23',
      );
    });
  });

  group('FeedingSchedule', () {
    test('a null feed_date is the legacy every-day schedule', () {
      expect(feed('legacy', '08:00').feedDate, isNull);
      expect(feed('legacy', '08:00').isDaily, isTrue);
      expect(feed('dated', '08:00', feedDate: '2026-11-24').isDaily, isFalse);
    });
  });

  group('groupFeedsByDate', () {
    test('sorts dates ascending with the every-day group last', () {
      final groups = groupFeedsByDate([
        feed('later-date', '10:00', feedDate: '2026-11-25'),
        feed('legacy-late', '08:30'),
        feed('earlier-date', '07:00', feedDate: '2026-11-24'),
        feed('legacy-early', '06:00'),
      ]);

      expect(groups.map((g) => g.date).toList(), [
        '2026-11-24',
        '2026-11-25',
        everyDayKey,
      ]);
    });

    test('sorts feeds inside a group by time', () {
      final groups = groupFeedsByDate([
        feed('late', '18:00', feedDate: '2026-11-24'),
        feed('early', '07:30', feedDate: '2026-11-24'),
        feed('mid', '12:15', feedDate: '2026-11-24'),
      ]);

      expect(groups.single.date, '2026-11-24');
      expect(groups.single.feeds.map((f) => f.id).toList(), [
        'early',
        'mid',
        'late',
      ]);
    });
  });

  group('firstConflict', () {
    test('blocks two drafts on the same date and time', () {
      expect(
        firstConflict(
          [
            draft('08:00', feedDate: '2026-11-24'),
            draft('08:00', feedDate: '2026-11-24'),
          ],
          const [],
        ),
        '2026-11-24 · 08:00',
      );
    });

    test('blocks a draft colliding with a legacy every-day row', () {
      expect(
        firstConflict(
          [draft('09:00')],
          [feed('legacy', '09:00')],
        ),
        'Every day · 09:00',
      );
    });

    test('does not treat the row being edited as a conflict', () {
      expect(
        firstConflict(
          [const FeedingDraft(id: 'saved', feedDate: '2026-11-24', time: '08:00', grams: 10, rotatorPwm: 255)],
          [feed('saved', '08:00', feedDate: '2026-11-24')],
        ),
        isNull,
      );
    });

    test('allows distinct times and dates', () {
      expect(
        firstConflict(
          [
            draft('08:00', feedDate: '2026-11-24'),
            draft('08:00', feedDate: '2026-11-25'),
          ],
          [feed('saved', '10:00', feedDate: '2026-11-24')],
        ),
        isNull,
      );
    });
  });
}
