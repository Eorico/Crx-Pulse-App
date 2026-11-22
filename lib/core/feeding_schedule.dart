import '../services/local_feeding_provider.dart';
import 'firmware_spec.dart';

/// Group key and conflict label for rows with no `feed_date`. Those rows are
/// the legacy schedules the ESP32 still fires every day.
const String everyDayKey = 'every-day';

/// One feed being saved. [feedDate] is a device-local `YYYY-MM-DD`; null
/// keeps the legacy every-day behaviour.
class FeedingDraft {
  final String? id;
  final String? feedDate;
  final String time;
  final int grams;
  final int rotatorPwm;

  const FeedingDraft({
    this.id,
    this.feedDate,
    required this.time,
    required this.grams,
    required this.rotatorPwm,
  });
}

/// Feeds sharing one device-local date. [date] is `everyDayKey` for the
/// legacy every-day group.
class FeedingDateGroup {
  final String? date;
  final List<FeedingSchedule> feeds;

  const FeedingDateGroup({
    this.date,
    required this.feeds,
  });
}

/// The device's current date. It fires schedules on NTP UTC+8, so a phone
/// in another zone must not decide which day is "today".
String deviceTodayDate({DateTime? now}) {
  final deviceNow = (now ?? DateTime.now()).toUtc().add(
        const Duration(hours: FirmwareSpec.deviceUtcOffsetHours),
      );
  return '${deviceNow.year.toString().padLeft(4, '0')}-'
      '${deviceNow.month.toString().padLeft(2, '0')}-'
      '${deviceNow.day.toString().padLeft(2, '0')}';
}

/// Groups feeds by device-local date, dates ascending and the legacy
/// every-day group last. Feeds within a group are ordered by time.
List<FeedingDateGroup> groupFeedsByDate(List<FeedingSchedule> feeds) {
  final byDate = <String, List<FeedingSchedule>>{};
  for (final feed in feeds) {
    final date = feed.feedDate ?? everyDayKey;
    (byDate[date] ??= <FeedingSchedule>[]).add(feed);
  }

  final dates = byDate.keys.toList()
    ..sort((a, b) {
      if (a == b) return 0;
      if (a == everyDayKey) return 1;
      if (b == everyDayKey) return -1;
      return a.compareTo(b);
    });

  return [
    for (final date in dates)
      FeedingDateGroup(
        date: date,
        feeds: (byDate[date]!.toList()..sort((a, b) => a.time.compareTo(b.time))),
      ),
  ];
}

/// The first `(date, time)` collision in [drafts], either against another
/// draft or against a saved [schedules] row. A draft editing a saved row
/// (matching [FeedingDraft.id]) does not collide with that row itself.
String? firstConflict(
  List<FeedingDraft> drafts,
  List<FeedingSchedule> schedules,
) {
  final draftKeys = <({String date, String time})>{};

  for (final draft in drafts) {
    final date = draft.feedDate ?? everyDayKey;
    final key = (date: date, time: draft.time);
    final collidesWithSaved = schedules.any((saved) =>
        saved.id != draft.id &&
        (date: saved.feedDate ?? everyDayKey, time: saved.time) == key);

    if (collidesWithSaved || draftKeys.contains(key)) {
      final label = date == everyDayKey ? 'Every day' : date;
      return '$label · ${draft.time}';
    }
    draftKeys.add(key);
  }
  return null;
}

/// The three kinds of write needed to make one date group match its edits.
class GroupUpdatePlan {
  final List<Map<String, dynamic>> updates;
  final List<Map<String, dynamic>> inserts;
  final List<String> deleteIds;

  const GroupUpdatePlan({
    required this.updates,
    required this.inserts,
    required this.deleteIds,
  });
}

/// Insert payloads for new feeds. A null draft date is a legacy every-day
/// row; callers pass drafts for the dates they selected in the calendar.
List<Map<String, dynamic>> feedingInsertRows({
  required String deviceId,
  required String userId,
  required List<FeedingDraft> drafts,
}) {
  return [
    for (final draft in drafts)
      {
        'device_id': deviceId,
        'user_id': userId,
        'feed_date': draft.feedDate,
        'time': draft.time,
        'grams': draft.grams,
        'rotator_pwm': draft.rotatorPwm,
        'active': true,
      },
  ];
}

/// Plans one group's writes. [date] is written verbatim: editing a legacy
/// group keeps NULL, while converting it writes the chosen date on every
/// row. Drafts without an id are new rows; saved ids absent from [edited]
/// are removed.
GroupUpdatePlan planGroupUpdate({
  required String deviceId,
  required String userId,
  required String? date,
  required List<FeedingSchedule> original,
  required List<FeedingDraft> edited,
}) {
  final editedById = <String, FeedingDraft>{};
  final newDrafts = <FeedingDraft>[];
  for (final draft in edited) {
    final id = draft.id;
    if (id == null) {
      newDrafts.add(draft);
    } else {
      editedById[id] = draft;
    }
  }

  final updates = <Map<String, dynamic>>[];
  for (final saved in original) {
    final draft = editedById[saved.id];
    if (draft == null) continue;
    updates.add({
      'id': saved.id,
      'device_id': deviceId,
      'user_id': userId,
      'feed_date': date,
      'time': draft.time,
      'grams': draft.grams,
      'rotator_pwm': draft.rotatorPwm,
      'active': saved.active,
    });
  }

  return GroupUpdatePlan(
    updates: updates,
    inserts: feedingInsertRows(
      deviceId: deviceId,
      userId: userId,
      drafts: [
        for (final draft in newDrafts)
          FeedingDraft(
            feedDate: date,
            time: draft.time,
            grams: draft.grams,
            rotatorPwm: draft.rotatorPwm,
          ),
      ],
    ),
    deleteIds: original
        .map((saved) => saved.id)
        .where((id) => !editedById.containsKey(id))
        .toList(),
  );
}
