import 'package:flutter_test/flutter_test.dart';
import 'package:crx_pulse/core/feeding_schedule.dart';
import 'package:crx_pulse/services/local_feeding_provider.dart';

void main() {
  FeedingDraft draft({
    String? id,
    String? feedDate,
    String time = '08:00',
    int grams = 10,
    int rotatorPwm = 255,
  }) =>
      FeedingDraft(
        id: id,
        feedDate: feedDate,
        time: time,
        grams: grams,
        rotatorPwm: rotatorPwm,
      );

  FeedingSchedule saved(
    String id,
    String time, {
    String? feedDate,
    bool active = true,
  }) =>
      FeedingSchedule(
        id: id,
        time: time,
        grams: 10,
        rotatorPwm: 255,
        active: active,
        feedDate: feedDate,
      );

  group('feedingInsertRows', () {
    test('emits one full insert row per draft', () {
      final rows = feedingInsertRows(
        deviceId: 'device-1',
        userId: 'user-1',
        drafts: [
          draft(
            feedDate: '2026-11-24',
            time: '08:00',
            grams: 15,
            rotatorPwm: 128,
          ),
          draft(time: '09:30'),
        ],
      );

      expect(rows, [
        {
          'device_id': 'device-1',
          'user_id': 'user-1',
          'feed_date': '2026-11-24',
          'time': '08:00',
          'grams': 15,
          'rotator_pwm': 128,
          'active': true,
        },
        {
          'device_id': 'device-1',
          'user_id': 'user-1',
          'feed_date': null,
          'time': '09:30',
          'grams': 10,
          'rotator_pwm': 255,
          'active': true,
        },
      ]);
    });
  });

  group('planGroupUpdate', () {
    final original = [saved('a', '08:00'), saved('b', '09:00')];

    test('a legacy group keeps feed_date null on every update', () {
      final plan = planGroupUpdate(
        deviceId: 'device-1',
        userId: 'user-1',
        date: null,
        original: original,
        edited: [
          draft(id: 'a', time: '08:00'),
          draft(id: 'b', time: '09:00'),
        ],
      );

      expect(plan.updates.map((row) => row['id']).toList(), ['a', 'b']);
      expect(plan.updates.map((row) => row['feed_date']).toList(), [null, null]);
      expect(plan.inserts, isEmpty);
      expect(plan.deleteIds, isEmpty);
    });

    test('a paused legacy row stays paused when the group is edited', () {
      final plan = planGroupUpdate(
        deviceId: 'device-1',
        userId: 'user-1',
        date: null,
        original: [saved('paused', '08:00', active: false)],
        edited: [draft(id: 'paused', time: '08:00')],
      );

      expect(plan.updates.single['active'], false);
      expect(plan.updates.single['feed_date'], isNull);
      expect(plan.inserts, isEmpty);
      expect(plan.deleteIds, isEmpty);
    });

    test('converting a legacy group writes the new date on every update', () {
      final plan = planGroupUpdate(
        deviceId: 'device-1',
        userId: 'user-1',
        date: '2026-11-24',
        original: original,
        edited: [
          draft(id: 'a', time: '08:00'),
          draft(id: 'b', time: '09:00'),
        ],
      );

      expect(
        plan.updates.map((row) => row['feed_date']).toList(),
        ['2026-11-24', '2026-11-24'],
      );
      expect(plan.inserts, isEmpty);
      expect(plan.deleteIds, isEmpty);
    });

    test('a draft without an id becomes an insert with the group date', () {
      final plan = planGroupUpdate(
        deviceId: 'device-1',
        userId: 'user-1',
        date: '2026-11-24',
        original: [saved('a', '08:00')],
        edited: [
          draft(id: 'a', time: '08:00'),
          draft(time: '12:00', grams: 20, rotatorPwm: 191),
        ],
      );

      expect(plan.inserts, [
        {
          'device_id': 'device-1',
          'user_id': 'user-1',
          'feed_date': '2026-11-24',
          'time': '12:00',
          'grams': 20,
          'rotator_pwm': 191,
          'active': true,
        },
      ]);
    });

    test('an original id missing from edited appears in deleteIds', () {
      final plan = planGroupUpdate(
        deviceId: 'device-1',
        userId: 'user-1',
        date: '2026-11-24',
        original: original,
        edited: [draft(id: 'a', time: '08:00')],
      );

      expect(plan.updates.map((row) => row['id']).toList(), ['a']);
      expect(plan.deleteIds, ['b']);
    });
  });
}
