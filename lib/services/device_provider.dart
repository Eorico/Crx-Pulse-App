import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves which ESP32 belongs to the signed-in user, and handles
/// pairing. In the Supabase build there is no secret device key — the
/// firmware authenticates with the project's anon key, so "pairing" just
/// records a row in `devices` claiming this device_id for the user, which
/// is what scopes the readings/schedules/commands shown in the app.
class DeviceProvider extends ChangeNotifier {
  final SupabaseClient _sb = Supabase.instance.client;

  String? deviceId;
  String? deviceName;
  bool loading = false;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  bool get hasDevice => deviceId != null;

  /// Live-watch the user's device rows (RLS limits this to their own).
  void start() {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    _sub?.cancel();
    _sub = _sb
        .from('devices')
        .stream(primaryKey: ['device_id'])
        .eq('user_id', uid)
        .listen((rows) {
      if (rows.isNotEmpty) {
        final d = rows.first;
        deviceId = d['device_id'] as String?;
        deviceName = (d['name'] as String?) ?? deviceId;
      } else {
        deviceId = null;
        deviceName = null;
      }
      notifyListeners();
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    deviceId = null;
    deviceName = null;
    notifyListeners();
  }

  /// Claim [id] for the current user (upsert). Returns the device id.
  /// No key to copy — the firmware already carries the Supabase anon key;
  /// you only set DEVICE_ID in the firmware to this same value.
  Future<String> pairDevice(String id, {String? name}) async {
    loading = true;
    notifyListeners();
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw 'Not signed in.';
      final cleanId = id.trim();
      final cleanName = (name != null && name.trim().isNotEmpty) ? name.trim() : cleanId;
      await _sb.from('devices').upsert({
        'device_id': cleanId,
        'user_id': uid,
        'name': cleanName,
        'active': true,
      });
      return cleanId;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
