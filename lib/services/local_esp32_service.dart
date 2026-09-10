import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The ESP32 now broadcasts its OWN WiFi network directly - your
/// phone connects to it like any other WiFi network. ESP32's SoftAP
/// mode always assigns itself 192.168.4.1 - this is fixed by the
/// WiFi library itself, not something either side configures.
const String esp32Ip = '192.168.4.1';
const int esp32Port = 8080;

/// Display-only, for the "can't reach the device" message - must
/// match ESP32_AP_SSID in the firmware.
const String esp32ApSsidHint = 'CRX-Pulse-ESP32';

enum Esp32ConnectionState { connecting, connected, unreachable }

/// Replaces the entire backend-dependent stack (AuthProvider,
/// SensorProvider's WebSocket, DeviceProvider, etc.) with one simple
/// polling service - no login, no account, no server beyond the
/// ESP32 itself. Polls /status every few seconds; the honesty
/// principle carries over from the backend days: a field genuinely
/// missing from the response (sensor disconnected) stays null here
/// too, never defaulted to a fake zero.
class LocalEsp32Service extends ChangeNotifier {
  Esp32ConnectionState state = Esp32ConnectionState.connecting;
  String? errorMessage;

  double? ph;
  double? ammonia;
  double? turbidity;
  double? waterTempC;
  double? ambientTempC;
  bool fanActive = false;
  int fanDutyPercent = 0;
  String? macAddress;
  DateTime? lastUpdated;

  Timer? _pollTimer;
  bool _disposed = false;

  void startPolling() {
    // FIX: called from multiple places now (MainTabScaffold centrally,
    // plus each screen's own initState as a safety net) - without this
    // guard, IndexedStack building all 4 screens immediately on
    // startup would create several overlapping Timer.periodic
    // instances all polling simultaneously, exactly the same class of
    // bug as the earlier duplicate-WebSocket-connection issue.
    if (_pollTimer != null) return;
    _pollOnce();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    if (_disposed) return;
    try {
      final res = await http.get(Uri.parse('http://$esp32Ip:$esp32Port/status')).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      ph = (data['ph'] as num?)?.toDouble();
      ammonia = (data['ammonia'] as num?)?.toDouble();
      turbidity = (data['turbidity'] as num?)?.toDouble();
      waterTempC = (data['water_temp_c'] as num?)?.toDouble();
      ambientTempC = (data['ambient_temp_c'] as num?)?.toDouble();
      fanActive = data['fan_active'] as bool? ?? false;
      fanDutyPercent = (data['fan_duty_percent'] as num?)?.toInt() ?? 0;
      macAddress = data['mac_address'] as String?;
      lastUpdated = DateTime.now();
      state = Esp32ConnectionState.connected;
      errorMessage = null;
    } catch (e) {
      state = Esp32ConnectionState.unreachable;
      errorMessage = "Can't reach the device. Connect your phone's WiFi directly to the "
          '"$esp32ApSsidHint" network broadcast by the ESP32, then try again.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> feedNow() async {
    try {
      final res = await http.post(Uri.parse('http://$esp32Ip:$esp32Port/feed')).timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }
}
