import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/firmware_spec.dart';

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
  const FeedingSchedule({
    required this.id,
    required this.time,
    required this.grams,
    required this.rotatorPwm,
    required this.active,
  });
}

/// Feeding — schedules and manual feeds — lives in Supabase so the ESP32
/// reads it directly over PostgREST. Scheduled feeding fires ON THE
/// DEVICE from its NTP clock, so it works even when the app is closed;
/// the app just manages the list and queues one-shot "feed now" commands.
class LocalFeedingProvider extends ChangeNotifier {
  final SupabaseClient _sb = Supabase.instance.client;

  List<FeedingSchedule> schedules = [];
  bool isLoading = false;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  String? get _uid => _sb.auth.currentUser?.id;

  /// Named fetchSchedules() so the call site keeps working; it opens a
  /// live stream of this user's schedules.
  Future<void> fetchSchedules() async {
    final uid = _uid;
    if (uid == null) return;
    isLoading = true;
    notifyListeners();
    _sub?.cancel();
    _sub = _sb
        .from('schedules')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('time')
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

  Future<void> toggleSchedule(String id, bool active) async {
    await _sb.from('schedules').update({'active': active}).eq('id', id);
  }

  Future<void> deleteSchedule(String id) async {
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
