import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/firmware_spec.dart';
import '../core/supabase_diagnosis.dart';

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
/// Three things have to be true for a line to appear, and when the
/// console is empty it is almost always one of them rather than a bug
/// here. [diagnosis] and [hasEverReceived] exist so the UI can say
/// which:
///
///   1. `supabase_schema.sql` has been run, so `device_logs` and the
///      `commands.value` column exist.
///   2. The ESP32 is running firmware v13 or later — earlier builds
///      never wrote to `device_logs` at all.
///   3. A device is paired to this account.
///
/// Verbose output (the sensor block, every 2 s) is not mirrored around
/// the clock — that would fill the table for a console nobody is
/// watching. [start] asks for it with a `log_stream` command and renews
/// that while the screen stays open; it lapses on the device a few
/// minutes after you leave. Event lines are always mirrored.
class DeviceLogProvider extends ChangeNotifier {
  final SupabaseClient _sb = Supabase.instance.client;

  List<DeviceLogLine> lines = [];

  /// True once the verbose request has been accepted by the database.
  /// Not a promise the device acted on it — only the log can show that.
  bool isStreaming = false;

  /// Non-null when something is broken. Carries the fix to offer.
  SupabaseDiagnosis? diagnosis;

  /// True once any row has arrived for this device, ever. Distinguishes
  /// "the table works and the device is quiet" (firmware too old, or
  /// nothing has happened yet) from "we never got a reply".
  bool hasEverReceived = false;

  /// True once the preflight read has succeeded, i.e. the table exists
  /// and RLS lets this account read it.
  bool tableReachable = false;

  bool _probing = false;
  bool get isProbing => _probing;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  Timer? _renewTimer;
  String? _deviceId;
  bool _disposed = false;

  String? get deviceId => _deviceId;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Open the feed for [deviceId] and ask the device for verbose output.
  ///
  /// Safe to call repeatedly — a call for the device already streaming
  /// just renews the request.
  Future<void> start(String deviceId) async {
    if (_deviceId == deviceId && _sub != null) {
      await _requestStream(FirmwareSpec.logStreamWindow.inSeconds);
      return;
    }

    await stop(notifyDevice: false);
    _deviceId = deviceId;
    diagnosis = null;
    _probing = true;
    _notify();

    // PREFLIGHT. The Realtime stream reports failures late and vaguely —
    // a missing table looks much like a dropped socket. A plain REST
    // read fails immediately with a Postgres error code, which is what
    // makes a precise diagnosis possible at all.
    final ok = await _probe(deviceId);
    _probing = false;
    if (!ok) {
      _notify();
      return;
    }

    _sub = _sb
        .from('device_logs')
        .stream(primaryKey: ['id'])
        .eq('device_id', deviceId)
        .order('id', ascending: false)
        .limit(FirmwareSpec.logScrollback)
        .listen(_onRows, onError: (Object e) {
      if (_disposed) return;
      diagnosis = SupabaseDiagnosis.from(e, what: 'stream the device log');
      _notify();
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

  /// One-shot read, both to confirm the table is usable and to populate
  /// the console immediately rather than waiting on the first Realtime
  /// event — which, for a quiet device, may never come.
  Future<bool> _probe(String deviceId) async {
    try {
      final rows = await _sb
          .from('device_logs')
          .select('id, message, created_at')
          .eq('device_id', deviceId)
          .order('id', ascending: false)
          .limit(FirmwareSpec.logScrollback);

      tableReachable = true;
      final fetched = (rows as List)
          .map((r) => DeviceLogLine.fromMap(r as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
      if (fetched.isNotEmpty) {
        lines = fetched;
        hasEverReceived = true;
      }
      return true;
    } catch (e) {
      tableReachable = false;
      diagnosis = SupabaseDiagnosis.from(e, what: 'read the device log');
      return false;
    }
  }

  /// Retry after a failure, from the UI's "Try again" button.
  Future<void> retry() async {
    final id = _deviceId;
    if (id == null) return;
    _deviceId = null; // force start() past its already-open check
    await start(id);
  }

  /// Close the feed. [notifyDevice] sends `log_stream 0` so verbose
  /// output stops now rather than timing out; it is skipped when
  /// stopping only to immediately restart.
  Future<void> stop({bool notifyDevice = true}) async {
    _renewTimer?.cancel();
    _renewTimer = null;
    await _sub?.cancel();
    _sub = null;

    if (_deviceId != null && notifyDevice) {
      await _requestStream(0);
    }
    _deviceId = null;
    isStreaming = false;
    _notify();
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
    } catch (e) {
      // This used to be `catch (_) {}`. A missing `commands.value`
      // column — exactly what you get from not re-running the schema —
      // was therefore invisible: verbose output silently never started
      // and the console just sat there looking broken.
      isStreaming = false;
      diagnosis =
          SupabaseDiagnosis.from(e, what: 'ask the device for verbose output');
    }
    _notify();
  }

  void _onRows(List<Map<String, dynamic>> rows) {
    if (_disposed) return;
    if (rows.isNotEmpty) hasEverReceived = true;
    // The query is newest-first; the console reads top-to-bottom in the
    // order the device printed them, so flip it here once rather than
    // in the widget on every build.
    lines = rows.map(DeviceLogLine.fromMap).toList().reversed.toList();
    if (diagnosis?.fault == SupabaseFault.offline) diagnosis = null;
    _notify();
  }

  /// Delete this device's stored log.
  Future<void> clear() async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      await _sb.from('device_logs').delete().eq('device_id', deviceId);
      lines = [];
      _notify();
    } catch (e) {
      diagnosis = SupabaseDiagnosis.from(e, what: 'clear the device log');
      _notify();
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
