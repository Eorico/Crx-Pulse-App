import 'dart:convert';

import 'package:crx_pulse/services/device_ap_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The fallback poller paints whatever this client returns straight onto
/// the dashboard, so what it accepts matters as much as what it fetches.
///
/// 192.168.4.1 is the ESP-IDF SoftAP gateway, and it is also a perfectly
/// ordinary home-router address. Everything here is about telling the
/// tank from a stranger, and about failing quietly on the far more
/// common case: no device on the other end at all.
void main() {
  /// Exactly what crx_pulse.ino's localReadingJson() serialises.
  const liveBody = '''
  {"device_id":"CRX-PULSE-01","ph":7.24,"ammonia":0.17,"turbidity":42.5,
   "turbidity_status":"Slightly Turbid","water_temp_c":26.4,
   "ambient_temp_c":31.2,"fan_active":true,"fan_percent":68,
   "ph_valid":true,"turbidity_valid":true,"water_temp_valid":true,
   "ambient_valid":true,"ammonia_valid":false}
  ''';

  /// And what handleApiStatus() serialises.
  const statusBody = '''
  {"device_id":"CRX-PULSE-01","firmware":"1.0.0","build_tag":"2026.11.23-motor-first",
   "sta_connected":false,"ap_active":true,"ap_clients":1,"uptime_s":412,"free_heap":151234}
  ''';

  DeviceApClient clientReturning(http.Response Function(http.Request) handler,
          {Duration? timeout}) =>
      DeviceApClient(
        timeout: timeout ?? const Duration(seconds: 4),
        clientFactory: () => MockClient((req) async => handler(req)),
      );

  DeviceApClient respondingWith(String body, {int status = 200}) =>
      clientReturning((_) => http.Response(body, status,
          headers: {'content-type': 'application/json'}));

  group('fetchLive', () {
    test('accepts the reading the firmware actually sends', () async {
      final live = await respondingWith(liveBody).fetchLive();

      expect(live, isNotNull);
      expect(live!['device_id'], 'CRX-PULSE-01');
      expect(live['ph'], 7.24);
      expect(live['ammonia_valid'], false);
      // Deliberately absent: the device has no clock while offline.
      expect(live.containsKey('recorded_at'), isFalse);
    });

    test('asks the SoftAP gateway for /api/live', () async {
      Uri? asked;
      await clientReturning((req) {
        asked = req.url;
        return http.Response(liveBody, 200);
      }).fetchLive();

      expect(asked.toString(), 'http://192.168.4.1/api/live');
    });

    test('returns null when nothing is listening', () async {
      // The ordinary case, hit on every poll while the tank's own WiFi
      // is working. It has to cost nothing but a null.
      final c = DeviceApClient(
        clientFactory: () =>
            MockClient((_) async => throw const SocketExceptionStub()),
      );
      expect(await c.fetchLive(), isNull);
    });

    test('returns null rather than hanging when the device is slow', () async {
      final c = DeviceApClient(
        timeout: const Duration(milliseconds: 40),
        clientFactory: () => MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return http.Response(liveBody, 200);
        }),
      );
      expect(await c.fetchLive(), isNull);
    });

    test('rejects a non-200', () async {
      expect(await respondingWith(liveBody, status: 500).fetchLive(), isNull);
      expect(await respondingWith('{"error":"no such route"}', status: 404)
          .fetchLive(), isNull);
    });

    test('rejects a body that is not JSON', () async {
      expect(await respondingWith('<html>Router login</html>').fetchLive(),
          isNull);
    });

    test('rejects JSON that is not an object', () async {
      expect(await respondingWith('[1,2,3]').fetchLive(), isNull);
    });

    test('rejects a stranger on 192.168.4.1 that answers with JSON', () async {
      // Some home routers hand out this subnet. A reading on the
      // dashboard has to have come from the tank.
      expect(await respondingWith('{"status":"ok","uptime":99}').fetchLive(),
          isNull);
    });

    test('rejects a payload with no device_id', () async {
      final body = jsonDecode(liveBody) as Map<String, dynamic>
        ..remove('device_id');
      expect(await respondingWith(jsonEncode(body)).fetchLive(), isNull);
    });

    test('rejects a payload with an empty device_id', () async {
      final body = jsonDecode(liveBody) as Map<String, dynamic>
        ..['device_id'] = '';
      expect(await respondingWith(jsonEncode(body)).fetchLive(), isNull);
    });

    test('rejects a payload missing a sensor the firmware always sends',
        () async {
      // Half a reading is not a reading: the dashboard would show
      // "Not Connected" for a sensor that is in fact fine.
      final body = jsonDecode(liveBody) as Map<String, dynamic>
        ..remove('water_temp_c');
      expect(await respondingWith(jsonEncode(body)).fetchLive(), isNull);
    });

    test('accepts a reading whose sensors are null', () async {
      // An invalid sensor arrives as null, and that is a real reading.
      final body = jsonDecode(liveBody) as Map<String, dynamic>
        ..['ph'] = null
        ..['ph_valid'] = false;
      final live = await respondingWith(jsonEncode(body)).fetchLive();

      expect(live, isNotNull);
      expect(live!['ph'], isNull);
      expect(live['ph_valid'], false);
    });
  });

  group('fetchStatus', () {
    test('accepts what handleApiStatus sends', () async {
      final s = await respondingWith(statusBody).fetchStatus();

      expect(s, isNotNull);
      expect(s!['ap_active'], true);
      expect(s['ap_clients'], 1);
      expect(s['sta_connected'], false);
      expect(s['build_tag'], '2026.11.23-motor-first');
    });

    test('still accepts an older status without a build tag', () async {
      // Older firmware is still the right device. The app shows no tag
      // for it rather than rejecting the whole status response.
      final body = jsonDecode(statusBody) as Map<String, dynamic>
        ..remove('build_tag');
      final s = await respondingWith(jsonEncode(body)).fetchStatus();

      expect(s, isNotNull);
      expect(s!['device_id'], 'CRX-PULSE-01');
    });

    test('rejects a reading, which is a different route', () async {
      expect(await respondingWith(liveBody).fetchStatus(), isNull);
    });

    test('asks for /api/status', () async {
      Uri? asked;
      await clientReturning((req) {
        asked = req.url;
        return http.Response(statusBody, 200);
      }).fetchStatus();

      expect(asked.toString(), 'http://192.168.4.1/api/status');
    });
  });
}

/// Stands in for the socket failure a phone gets when 192.168.4.1 is not
/// there. Any thrown exception has to come back as null, so the exact
/// type is beside the point — which is what this proves.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketException: Host unreachable (192.168.4.1)';
}
