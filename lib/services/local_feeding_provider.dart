import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/feeding_schedule.dart';
import '../core/firmware_spec.dart';
import 'offline_device_link.dart';

/// A feeding schedule row in Supabase `schedules`. `grams` is one of the
/// fixed dropdown values (5/10/15/20/25/30) the firmware has calibrated
/// open-times for; `rotatorPwm` is one of the five speeds setMotor1()
/// was bench-tested at.
class FeedingSchedule {
  final String id;
  final String time;   // "HH:MM" (device-local, UTC+8)
  final int grams;
  final int rotatorPwm;
  final bool active;

  /// Device-local `YYYY-MM-DD`. Null is a legacy row the ESP32 fires
  /// every day.
  final String? feedDate;

  /// The device this row belongs to. Null on older rows, which the active
  /// device inherits.
  final String? deviceId;

  const FeedingSchedule({
    required this.id,
    required this.time,
    required this.grams,
    required this.rotatorPwm,
    required this.active,
    this.feedDate,
    this.deviceId,
  });

  bool get isDaily => feedDate == null;
}

/// Feeding — schedules and manual feeds — lives in Supabase so the ESP32
/// reads it directly over PostgREST. Scheduled feeding fires ON THE
/// DEVICE from its NTP clock, so it works even when the app is closed;
/// the app just manages the list and queues one-shot "feed now" commands.
class LocalFeedingProvider extends ChangeNotifier {
  final SupabaseClient _sb;
  final OfflineDeviceLink? _deviceLink;

  LocalFeedingProvider({SupabaseClient? client, OfflineDeviceLink? deviceLink})
      : _sb = client ?? Supabase.instance.client,
        _deviceLink = deviceLink;

  /// True only after a reading has arrived over the board's own AP. The AP
  /// keeps running even when the tank has internet, so connection state
  /// alone cannot decide which transport to use.
  bool get _offline => _deviceLink?.isOfflineDirect ?? false;

  /// Device-side slots are keyed by their index in the board's cache. The
  /// `ap-` prefix keeps them distinct from Supabase UUIDs in the UI.
  static int? _apIndex(String id) =>
      id.startsWith('ap-') ? int.tryParse(id.substring(3)) : null;

  /// AP writes return false when the board rejects them. Without this the
  /// caller reports success for a schedule that was never saved.
  void _requireAck(bool acknowledged) {
    if (!acknowledged) {
      throw StateError('The device did not acknowledge the change.');
    }
  }

  List<FeedingSchedule> schedules = [];
  bool isLoading = false;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  String? get _uid => _sb.auth.currentUser?.id;

  /// Rows for [deviceId] only. Rows with no device id predate the column and
  /// are treated as belonging to whichever device is active. The stream
  /// itself is scoped by user, not device, so the UI must call this before
  /// showing or validating schedules.
  List<FeedingSchedule> schedulesForDevice(String? deviceId) =>
      deviceId == null
          ? const []
          : schedules
              .where((s) => s.deviceId == null || s.deviceId == deviceId)
              .toList();

  /// Named fetchSchedules() so the call site keeps working; it opens a
  /// live stream of this user's schedules.
  Future<void> fetchSchedules() async {
    if (_offline) {
      // A stream opened while online would keep overwriting the board's
      // rows with Supabase data that the device cannot even read.
      await _sub?.cancel();
      _sub = null;
      final rows = await _deviceLink!.readSchedules();
      if (rows == null) return;
      schedules = rows.map((r) => FeedingSchedule(
            id: 'ap-${r['index']}',
            time: (r['time'] as String?) ?? '00:00',
            grams: (r['grams'] as num?)?.toInt() ?? 10,
            rotatorPwm: (r['rotator_pwm'] as num?)?.toInt() ??
                FirmwareSpec.rotatorDefaultPwm,
            active: r['active'] as bool? ?? true,
            feedDate: r['feed_date'] as String?,
          )).toList();
      isLoading = false;
      notifyListeners();
      return;
    }

    final uid = _uid;
    if (uid == null) return;
    isLoading = true;
    notifyListeners();
    _sub?.cancel();
    _sub = _sb
        .from('schedules')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('feed_date', ascending: true)
        .order('time', ascending: true)
        .listen((rows) {
      schedules = rows.map((m) => FeedingSchedule(
            id: m['id'].toString(),
            time: (m['time'] as String?) ?? '00:00',
            grams: (m['grams'] as num?)?.toInt() ?? 10,
            // Rows written before rotator_pwm existed read as null;
            // show them as the full speed the firmware used to use
            // unconditionally, which is what they will actually do.
            rotatorPwm: (m['rotator_pwm'] as num?)?.toInt() ??
                FirmwareSpec.rotatorDefaultPwm,
            active: m['active'] as bool? ?? true,
            feedDate: m['feed_date'] as String?,
            deviceId: m['device_id'] as String?,
          )).toList();
      isLoading = false;
      notifyListeners();
    });
  }

  Future<void> createSchedule(
    String deviceId,
    String time,
    int grams, {
    int rotatorPwm = FirmwareSpec.rotatorDefaultPwm,
  }) async {
    if (_offline) {
      _requireAck(await _deviceLink!.addSchedule(
          time: time, grams: grams, pwm: rotatorPwm));
      await fetchSchedules();
      return;
    }
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('schedules').insert({
      'device_id': deviceId,
      'user_id': uid,
      'time': time,
      'grams': grams,
      'rotator_pwm': rotatorPwm,
      'active': true,
    });
  }

  /// Writes a batch of dated feeds, one `schedules` row per (date, time).
  Future<void> createSchedules(String deviceId, List<FeedingDraft> drafts) async {
    if (_offline) {
      try {
        for (final draft in drafts) {
          _requireAck(await _deviceLink!.addSchedule(
            time: draft.time,
            feedDate: draft.feedDate,
            grams: draft.grams,
            pwm: draft.rotatorPwm,
          ));
        }
      } finally {
        await fetchSchedules();
      }
      return;
    }
    final uid = _uid;
    if (uid == null) return;
    final rows = feedingInsertRows(
      deviceId: deviceId,
      userId: uid,
      drafts: drafts,
    );
    if (rows.isEmpty) return;
    await _sb.from('schedules').insert(rows);
  }

  /// Replaces the rows of one date group with [edited]. [date] is the group's
  /// date (null for the legacy every-day group), written to every row.
  Future<void> updateScheduleGroup(
    String deviceId,
    String? date,
    List<FeedingSchedule> original,
    List<FeedingDraft> edited,
  ) async {
    if (_offline) {
      try {
        final editedById = <String, FeedingDraft>{
          for (final d in edited) if (d.id != null) d.id!: d,
        };
        // Overwrites first: they do not shift any index.
        for (final saved in original) {
          final draft = editedById[saved.id];
          final index = _apIndex(saved.id);
          if (draft == null || index == null) continue;
          _requireAck(await _deviceLink!.addSchedule(
            time: draft.time,
            feedDate: date,
            grams: draft.grams,
            pwm: draft.rotatorPwm,
            active: saved.active,
            index: index,
          ));
        }
        for (final draft in edited) {
          if (draft.id != null) continue;
          _requireAck(await _deviceLink!.addSchedule(
            time: draft.time,
            feedDate: date,
            grams: draft.grams,
            pwm: draft.rotatorPwm,
          ));
        }
        // Removals last, highest index first, so lower indices stay put.
        final removed = original
            .where((s) => !editedById.containsKey(s.id))
            .map((s) => _apIndex(s.id))
            .whereType<int>()
            .toList()
          ..sort((a, b) => b.compareTo(a));
        for (final index in removed) {
          _requireAck(await _deviceLink!.removeSchedule(index));
        }
      } finally {
        // Even a rejected batch leaves partial changes on the board; show
        // what actually landed rather than the state we hoped to write.
        await fetchSchedules();
      }
      return;
    }
    final uid = _uid;
    if (uid == null) return;
    final plan = planGroupUpdate(
      deviceId: deviceId,
      userId: uid,
      date: date,
      original: original,
      edited: edited,
    );
    // Removed rows must go before new ones: inserting a replacement at the
    // same (date, time) first would briefly leave two rows for that slot.
    // These PostgREST calls are separate requests, not a transaction: if a
    // later one fails, earlier writes stay committed. Callers catch the
    // error, report it and re-fetch, so the live list shows what actually
    // landed rather than a partial write pretending to be complete.
    if (plan.deleteIds.isNotEmpty) {
      await _sb
          .from('schedules')
          .delete()
          .inFilter('id', plan.deleteIds.toList());
    }
    for (final row in plan.updates) {
      await _sb.from('schedules').update(row).eq('id', row['id']);
    }
    if (plan.inserts.isNotEmpty) {
      await _sb.from('schedules').insert(plan.inserts);
    }
  }

  /// Deletes a whole date group (or any other set of schedule ids).
  Future<void> deleteSchedules(Set<String> ids) async {
    if (ids.isEmpty) return;
    if (_offline) {
      try {
        final indices = ids.map(_apIndex).whereType<int>().toList()
          ..sort((a, b) => b.compareTo(a));
        for (final index in indices) {
          _requireAck(await _deviceLink!.removeSchedule(index));
        }
      } finally {
        await fetchSchedules();
      }
      return;
    }
    await _sb.from('schedules').delete().inFilter('id', ids.toList());
  }

  Future<void> toggleSchedule(String id, bool active) async {
    if (_offline) {
      final index = _apIndex(id);
      final saved = schedules.where((s) => s.id == id).firstOrNull;
      if (index == null || saved == null) return;
      _requireAck(await _deviceLink!.addSchedule(
        time: saved.time,
        feedDate: saved.feedDate,
        grams: saved.grams,
        pwm: saved.rotatorPwm,
        active: active,
        index: index,
      ));
      await fetchSchedules();
      return;
    }
    await _sb.from('schedules').update({'active': active}).eq('id', id);
  }

  Future<void> deleteSchedule(String id) async {
    if (_offline) {
      final index = _apIndex(id);
      if (index == null) return;
      _requireAck(await _deviceLink!.removeSchedule(index));
      await fetchSchedules();
      return;
    }
    await _sb.from('schedules').delete().eq('id', id);
  }

  /// Manual feed — queues a feed_now command. The ESP32 picks it up on
  /// its next poll (~5 s), dispenses the grams, then runs the rotator
  /// at [rotatorPwm].
  Future<bool> feedNow(
    String deviceId,
    int grams, {
    int rotatorPwm = FirmwareSpec.rotatorDefaultPwm,
  }) async {
    if (_offline) {
      return _deviceLink!.feed(grams, rotatorPwm);
    }
    final uid = _uid;
    if (uid == null) return false;
    await _sb.from('commands').insert({
      'device_id': deviceId,
      'user_id': uid,
      'type': DeviceCommand.feedNow,
      'grams': grams,
      'rotator_pwm': rotatorPwm,
      'handled': false,
    });
    return true;
  }

  /// No-op kept for call-site compatibility: scheduled feeding runs on
  /// the ESP32 itself (NTP), not the phone.
  Future<void> checkDueSchedules(dynamic esp32) async {}

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
