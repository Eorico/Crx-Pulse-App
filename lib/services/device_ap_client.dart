import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Talks to the ESP32's offline access point.
///
/// When the tank's WiFi goes away the firmware raises its own network
/// (`CRX-Pulse-XXXXXX`, see serviceAccessPoint() in crx_pulse.ino) and
/// serves two routes on 192.168.4.1 — the SoftAP gateway address, which
/// is fixed by the ESP-IDF default and so needs no discovery:
///
///   GET /api/live    the current reading, in `readings` column names
///   GET /api/status  device id, firmware, uptime, client count
///
/// Everything here fails quietly. On the tank's normal WiFi there is no
/// 192.168.4.1 to answer, and that is not an error — it is the ordinary
/// case, hit once every poll, and must cost nothing but a timeout.
class DeviceApClient {
  const DeviceApClient({
    this.baseUrl = 'http://192.168.4.1',
    this.timeout = const Duration(seconds: 4),
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory;

  /// The SoftAP gateway. Fixed, not configurable at runtime: the
  /// firmware does not choose it either.
  final String baseUrl;

  /// Short on purpose. A phone that is not on the device's AP must find
  /// that out quickly, because this runs on a repeating timer. Long
  /// enough, though, to ride out the ~1 s the firmware can spend in a
  /// DS18B20 conversion before it gets back to serving HTTP.
  final Duration timeout;

  final http.Client Function()? _clientFactory;

  /// The device's current reading, or null if the AP did not answer or
  /// answered with something that is not one of our readings.
  Future<Map<String, dynamic>?> fetchLive() => _getJson('/api/live', _isReading);

  /// The device's own view of itself — used to confirm we are talking to
  /// a CRX-Pulse board and not to whatever else happens to live on
  /// 192.168.4.1.
  Future<Map<String, dynamic>?> fetchStatus() =>
      _getJson('/api/status', _isStatus);

  Future<Map<String, dynamic>?> _getJson(
      String path, bool Function(Map<String, dynamic>) looksRight) async {
    final client = _clientFactory?.call() ?? http.Client();
    try {
      final res =
          await client.get(Uri.parse('$baseUrl$path')).timeout(timeout);
      if (res.statusCode != 200) return null;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      // Guard against a stranger on 192.168.4.1: some home routers hand
      // out that subnet, and a reading painted on the dashboard has to
      // have come from the tank.
      if (!looksRight(decoded)) return null;
      return decoded;
    } catch (_) {
      // Socket refused, host unreachable, timeout, malformed JSON — all
      // mean the same thing here: no device on the other end.
      return null;
    } finally {
      client.close();
    }
  }

  /// The reading keys the firmware's localReadingJson() always sends.
  static const List<String> _readingKeys = [
    'ph',
    'ammonia',
    'turbidity',
    'water_temp_c',
    'ambient_temp_c',
  ];

  static bool _hasDeviceId(Map<String, dynamic> d) {
    final id = d['device_id'];
    return id is String && id.isNotEmpty;
  }

  static bool _isReading(Map<String, dynamic> d) =>
      _hasDeviceId(d) && _readingKeys.every(d.containsKey);

  static bool _isStatus(Map<String, dynamic> d) =>
      _hasDeviceId(d) && d.containsKey('ap_active') && d.containsKey('uptime_s');
}
