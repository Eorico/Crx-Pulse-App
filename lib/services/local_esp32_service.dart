import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/firmware_spec.dart';

/// Live sensor readings — now a Supabase Realtime subscription on the
/// `readings` table (was a Firestore stream).
///
///   ESP32 -> Supabase readings table -> this .stream() -> the UI
///
/// The class name, public fields, and the Esp32ConnectionState enum are
/// unchanged, so every screen that reads them keeps working — only the
/// data SOURCE moved. Connection semantics are identical: anything other
/// than a fresh reading clears every value to null so the UI shows
/// "Not Connected" everywhere rather than a stale number.
enum Esp32ConnectionState { connecting, connected, unreachable }

/// A reading counts as live if it arrived within this window: three of
/// the firmware's push intervals, so one dropped or slow insert does
/// not read as a disconnection. Defined in [FirmwareSpec] alongside the
/// firmware's own CLOUD_READING_INTERVAL so the two stay in step.
const Duration _freshWindow = FirmwareSpec.freshWindow;

class LocalEsp32Service extends ChangeNotifier {
  final SupabaseClient _sb = Supabase.instance.client;

  Esp32ConnectionState state = Esp32ConnectionState.connecting;
  String? errorMessage;

  // Six readings the app displays.
  double? ph;
  double? ammonia;        // mg/L estimate
  double? turbidity;      // percent (0 = clear, 100 = highly turbid)
  String? turbidityStatus;
  double? waterTempC;
  double? ambientTempC;   // DHT11 — the app's "Housing Temperature"
  bool fanActive = false;
  int fanDutyPercent = 0;

  String? macAddress;     // retained for API compatibility; unused now
  DateTime? lastUpdated;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  Timer? _staleTimer;
  bool _disposed = false;
  String? _deviceId;

  bool get isTracking => state == Esp32ConnectionState.connected;

  void _clearReadings() {
    ph = null;
    ammonia = null;
    turbidity = null;
    turbidityStatus = null;
    waterTempC = null;
    ambientTempC = null;
    fanActive = false;
    fanDutyPercent = 0;
  }

  /// Kept named startPolling() so call sites don't change. Resolves the
  /// user's paired device, then opens a live stream of its newest reading.
  /// Safe to call again after pairing — the early-return paths below do
  /// not create a subscription, so a later call re-attempts cleanly.
  Future<void> startPolling() async {
    if (_sub != null) return;

    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      _clearReadings();
      state = Esp32ConnectionState.unreachable;
      errorMessage = 'Not signed in.';
      notifyListeners();
      return;
    }

    // Which device is paired to this user?
    try {
      final devs = await _sb.from('devices').select('device_id').eq('user_id', uid).limit(1);
      if (devs.isEmpty) {
        _clearReadings();
        state = Esp32ConnectionState.unreachable;
        errorMessage = 'No paired device yet — pair one in Setup.';
        notifyListeners();
        return;
      }
      _deviceId = devs.first['device_id'] as String?;
    } catch (_) {
      _clearReadings();
      state = Esp32ConnectionState.unreachable;
      errorMessage = "Can't reach the cloud. Check this phone's internet connection.";
      notifyListeners();
      return;
    }

    _sub = _sb
        .from('readings')
        .stream(primaryKey: ['id'])
        .eq('device_id', _deviceId!)
        .order('recorded_at', ascending: false)
        .limit(1)
        .listen(_onRows, onError: (_) {
      _clearReadings();
      state = Esp32ConnectionState.unreachable;
      errorMessage = "Can't reach the cloud. Check this phone's internet connection.";
      if (!_disposed) notifyListeners();
    });

    // Flip to "Not Connected" by the clock when the device stops sending.
    _staleTimer ??= Timer.periodic(const Duration(seconds: 5), (_) => _reevaluate());
  }

  void stopPolling() {
    _sub?.cancel();
    _sub = null;
    _staleTimer?.cancel();
    _staleTimer = null;
    _deviceId = null;
    _clearReadings();
    state = Esp32ConnectionState.connecting;
    notifyListeners();
  }

  void _onRows(List<Map<String, dynamic>> rows) {
    if (_disposed) return;

    if (rows.isEmpty) {
      _clearReadings();
      state = Esp32ConnectionState.connecting;
      errorMessage = 'Waiting for the first reading from your device.';
      notifyListeners();
      return;
    }

    final d = rows.first;
    final ts = d['recorded_at'];
    final readingTime = ts is String ? (DateTime.tryParse(ts) ?? DateTime.now()) : DateTime.now();

    final fresh = DateTime.now().difference(readingTime).abs() <= _freshWindow;
    if (!fresh) {
      lastUpdated = readingTime.toLocal();
      _clearReadings();
      state = Esp32ConnectionState.unreachable;
      errorMessage = 'Not Connected — no live readings from your device.';
      notifyListeners();
      return;
    }

    double? asNum(String k) => (d[k] as num?)?.toDouble();
    // A sensor the firmware flagged invalid is shown as "Not Connected".
    bool ok(String k) => d[k] is bool ? d[k] as bool : true;

    ph              = ok('ph_valid') ? asNum('ph') : null;
    ammonia         = ok('ammonia_valid') ? asNum('ammonia') : null;
    turbidity       = ok('turbidity_valid') ? asNum('turbidity') : null;
    turbidityStatus = d['turbidity_status'] as String?;
    waterTempC      = ok('water_temp_valid') ? asNum('water_temp_c') : null;
    ambientTempC    = ok('ambient_valid') ? asNum('ambient_temp_c') : null;
    fanActive       = d['fan_active'] as bool? ?? false;
    fanDutyPercent  = (d['fan_percent'] as num?)?.toInt() ?? 0;

    lastUpdated = readingTime.toLocal();
    _reevaluate(justReceived: true);
  }

  void _reevaluate({bool justReceived = false}) {
    if (_disposed || lastUpdated == null) return;

    final fresh = DateTime.now().difference(lastUpdated!).abs() <= _freshWindow;

    if (!fresh) {
      if (state != Esp32ConnectionState.unreachable) {
        _clearReadings();
        state = Esp32ConnectionState.unreachable;
        errorMessage = 'Not Connected — no live readings from your device.';
        notifyListeners();
      }
      return;
    }

    const next = Esp32ConnectionState.connected;
    errorMessage = null;
    if (next != state || justReceived) {
      state = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _staleTimer?.cancel();
    super.dispose();
  }
}
