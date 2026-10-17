import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/firmware_spec.dart';

/// One line of the ESP32's serial output.
class DeviceLogLine {
  /// `device_logs.id` — a bigserial. Ordering is by this, not by time:
  /// several lines routinely share a millisecond, and sorting those by
  /// timestamp would shuffle them out of the order they were printed.
  final int id;
  final String message;
  final DateTime at;

  const DeviceLogLine({required this.id, required this.message, required this.at});

  factory DeviceLogLine.fromMap(Map<String, dynamic> m) => DeviceLogLine(
        id: (m['id'] as num).toInt(),
        message: (m['message'] as String?) ?? '',
        at: DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

/// Live feed of the device's serial output, for Test Components.
///
/// The phone has no serial or USB link to the ESP32 — it only reaches it
/// through Supabase. So "show the serial output" means exactly this: the
/// firmware mirrors every line it prints into `device_logs`, and this
/// subscribes to that table. What the console renders is the same text a
/// serial monitor would show.
///
/// Verbose output (the sensor block, printed every 2 s) is not mirrored
/// around the clock — that would fill the table for a console nobody is
/// watching. [start] asks the device for it with a `log_stream` command
/// and renews that request while the screen stays open; it lapses on the
/// device a few minutes after you leave. Event lines (feeds, commands,
/// errors) are always mirrored, so there is history waiting when you
/// come back.
class DeviceLogProvider extends ChangeNotifier {
  final SupabaseClient _sb = Supabase.instance.client;

  List<DeviceLogLine> lines = [];
  bool isStreaming = false;
  String? errorMessage;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  Timer? _renewTimer;
  String? _deviceId;
  bool _disposed = false;

  /// Open the feed for [deviceId] and ask the device for verbose output.
  Future<void> start(String deviceId) async {
    if (_deviceId == deviceId && _sub != null) {
      // Already open — just push the deadline out again.
      await _requestStream(FirmwareSpec.logStreamWindow.inSeconds);
      return;
    }

    await stop();
    _deviceId = deviceId;
    errorMessage = null;

    _sub = _sb
        .from('device_logs')
        .stream(primaryKey: ['id'])
        .eq('device_id', deviceId)
        .order('id', ascending: false)
        .limit(FirmwareSpec.logScrollback)
        .listen(_onRows, onError: (Object e) {
      if (_disposed) return;
      errorMessage = "Can't reach the cloud — check this phone's connection.";
      notifyListeners();
    });

    await _requestStream(FirmwareSpec.logStreamWindow.inSeconds);

    // Renew well before the device's deadline lapses, so the feed never
    // goes quiet while the screen is still open.
    _renewTimer?.cancel();
    _renewTimer = Timer.periodic(
      FirmwareSpec.logStreamRenew,
      (_) => _requestStream(FirmwareSpec.logStreamWindow.inSeconds),
    );
  }

  /// Close the feed and tell the device to stop verbose output now,
  /// rather than leaving it to time out.
  Future<void> stop() async {
    _renewTimer?.cancel();
    _renewTimer = null;
    await _sub?.cancel();
    _sub = null;

    if (_deviceId != null) {
      await _requestStream(0);
      _deviceId = null;
    }

    isStreaming = false;
    if (!_disposed) notifyListeners();
  }

  /// Queue a `log_stream` command. [seconds] of 0 switches it off.
  Future<void> _requestStream(int seconds) async {
    final deviceId = _deviceId;
    final uid = _sb.auth.currentUser?.id;
    if (deviceId == null || uid == null) return;

    try {
      await _sb.from('commands').insert({
        'device_id': deviceId,
        'user_id': uid,
        'type': DeviceCommand.logStream,
        'value': seconds,
        'handled': false,
      });
      isStreaming = seconds > 0;
    } catch (_) {
      // A failed request is not fatal: event lines still arrive, so the
      // console keeps working with less detail.
      isStreaming = false;
    }
    if (!_disposed) notifyListeners();
  }

  void _onRows(List<Map<String, dynamic>> rows) {
    if (_disposed) return;
    // The query is newest-first; the console reads top-to-bottom in the
    // order the device printed them, so flip it here once rather than
    // in the widget on every build.
    lines = rows.map(DeviceLogLine.fromMap).toList().reversed.toList();
    errorMessage = null;
    notifyListeners();
  }

  /// Delete this device's stored log. The console empties as the
  /// Realtime subscription reports the rows going away.
  Future<void> clear() async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      await _sb.from('device_logs').delete().eq('device_id', deviceId);
      lines = [];
      notifyListeners();
    } catch (e) {
      errorMessage = 'Could not clear the log.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _renewTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
