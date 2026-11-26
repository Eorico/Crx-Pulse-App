import 'dart:convert';

import 'package:crx_pulse/core/feeding_schedule.dart';
import 'package:crx_pulse/services/device_ap_client.dart';
import 'package:crx_pulse/services/device_provider.dart';
import 'package:crx_pulse/services/device_test_provider.dart';
import 'package:crx_pulse/services/local_feeding_provider.dart';
import 'package:crx_pulse/services/offline_device_link.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// When the board cannot reach the router it raises its own access point.
/// The app must keep doing everything it does through Supabase — feed,
/// test the actuators, manage schedules — over that link instead.
///
/// A stranger on 192.168.4.1 is still a stranger: every reply has to carry
/// the board's own acknowledgement before an action is treated as done.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async {
        if (call.method == 'getAll') return <String, Object>{};
        return null;
      },
    );
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-key',
    );
  });

  http.Response okResponse() => http.Response(
        jsonEncode({'ok': true, 'device_id': 'CRX-PULSE-01'}),
        200,
        headers: {'content-type': 'application/json'},
      );

  group('DeviceApClient actions', () {
    test('each action posts to its own route with the device id', () async {
      final calls = <String, Map<String, dynamic>>{};
      final client = DeviceApClient(
        clientFactory: () => MockClient((req) async {
          calls[req.url.path] = jsonDecode(req.body) as Map<String, dynamic>;
          return okResponse();
        }),
      );

      expect(await client.postTime(1730000000, 'CRX-PULSE-01'), isTrue);
      expect(await client.postFeed('CRX-PULSE-01', 15, 180), isTrue);
      expect(
          await client.postCommand('CRX-PULSE-01', 'servo_open', value: 90),
          isTrue);
      expect(
          await client.postSchedule('CRX-PULSE-01',
              time: '08:00', feedDate: '2026-11-24', grams: 15, pwm: 180),
          isTrue);
      expect(await client.deleteSchedule('CRX-PULSE-01', 2), isTrue);

      expect(calls.keys, contains('/api/time'));
      expect(calls['/api/time']!['epoch_seconds'], 1730000000);
      expect(calls['/api/feed']!['grams'], 15);
      expect(calls['/api/feed']!['rotator_pwm'], 180);
      expect(calls['/api/command']!['type'], 'servo_open');
      expect(calls['/api/schedules']!['feed_date'], '2026-11-24');
      expect(calls['/api/schedules/delete']!['index'], 2);
      expect(calls.values.every((b) => b['device_id'] == 'CRX-PULSE-01'),
          isTrue);
    });

    test('a null feed date is omitted, not sent as the text "null"', () async {
      Map<String, dynamic>? body;
      final client = DeviceApClient(
        clientFactory: () => MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return okResponse();
        }),
      );

      await client.postSchedule('CRX-PULSE-01',
          time: '23:30', grams: 10, pwm: 255);

      expect(body!.containsKey('feed_date'), isFalse);
    });

    test('a non-200 or an unacknowledged reply is a failure', () async {
      final refused = DeviceApClient(
        clientFactory: () => MockClient((_) async => http.Response('{}', 500)),
      );
      final stranger = DeviceApClient(
        clientFactory: () =>
            MockClient((_) async => http.Response('{"status":"ok"}', 200)),
      );

      expect(await refused.postFeed('CRX-PULSE-01', 10, 255), isFalse);
      expect(await stranger.postFeed('CRX-PULSE-01', 10, 255), isFalse);
    });

    test('a socket failure returns false rather than throwing', () async {
      final client = DeviceApClient(
        clientFactory: () => MockClient((_) async => throw StateError('offline')),
      );
      expect(await client.postFeed('CRX-PULSE-01', 10, 255), isFalse);
    });

    test('cached schedules keep their board id, index and date', () async {
      final client = DeviceApClient(
        clientFactory: () => MockClient((_) async => http.Response(
              jsonEncode({
                'device_id': 'CRX-PULSE-01',
                'schedules': [
                  {
                    'index': 2,
                    'time': '08:00',
                    'grams': 15,
                    'rotator_pwm': 180,
                    'active': true,
                    'device_id': 'CRX-PULSE-01',
                  }
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

      final rows = await client.fetchSchedules();
      expect(rows, hasLength(1));
      expect(rows!.first['index'], 2);
      expect(rows.first['time'], '08:00');
      expect(rows.first['feed_date'], isNull);
    });
  });

  group('offline routing', () {
    late _FakeLink link;

    setUp(() => link = _FakeLink());

    test('a manual feed goes to the board when offline', () async {
      final provider = LocalFeedingProvider(deviceLink: link);
      addTearDown(provider.dispose);

      final sent = await provider.feedNow('CRX-PULSE-01', 15,
          rotatorPwm: 180);

      expect(sent, isTrue);
      expect(link.feedCalls, [
        isA<Map<String, int>>()
            .having((m) => m['grams']!, 'grams', 15)
            .having((m) => m['pwm']!, 'pwm', 180)
      ]);
    });

    test('test commands go to the board when offline', () async {
      final provider = DeviceTestProvider(deviceLink: link);
      addTearDown(provider.dispose);

      expect(await provider.openServo('CRX-PULSE-01'), isTrue);
      expect(await provider.runMotor('CRX-PULSE-01'), isTrue);

      expect(link.commandCalls.map((c) => c.type),
          ['servo_open', 'motor_test']);
    });

    test('an online provider does not touch the board', () async {
      link.isOfflineDirect = false;
      final provider = LocalFeedingProvider(deviceLink: link);
      addTearDown(provider.dispose);

      // Not signed in: the Supabase path exits before any network call,
      // which is enough to prove the AP was never asked.
      await provider.feedNow('CRX-PULSE-01', 10);

      expect(link.feedCalls, isEmpty);
    });

    test('a rejected offline write is reported instead of succeeding', () async {
      link.acknowledgeWrites = false;
      final provider = LocalFeedingProvider(deviceLink: link);
      addTearDown(provider.dispose);

      await expectLater(
        provider.createSchedules('CRX-PULSE-01', [
          const FeedingDraft(time: '08:00', grams: 10, rotatorPwm: 255),
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test('an offline cold start adopts the board id for the controls', () {
      final device = DeviceProvider();
      addTearDown(device.stop);

      expect(device.hasDevice, isFalse);
      device.adoptOfflineDeviceId('CRX-PULSE-01');
      expect(device.deviceId, 'CRX-PULSE-01');

      // A real pairing is authoritative; the AP id must never replace it.
      device.adoptOfflineDeviceId('OTHER-BOARD');
      expect(device.deviceId, 'CRX-PULSE-01');
    });
  });
}

class _FakeLink implements OfflineDeviceLink {
  @override
  bool isOfflineDirect = true;

  final List<Map<String, int>> feedCalls = [];
  final List<({String type, int? value})> commandCalls = [];
  bool acknowledgeWrites = true;

  @override
  Future<bool> seedClock(int epochSeconds) async => true;

  @override
  Future<bool> feed(int grams, int pwm) async {
    feedCalls.add({'grams': grams, 'pwm': pwm});
    return true;
  }

  @override
  Future<bool> command(String type, {int? grams, int? pwm, int? value}) async {
    commandCalls.add((type: type, value: value));
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>?> readSchedules() async => [];

  @override
  Future<bool> addSchedule({
    required String time,
    String? feedDate,
    required int grams,
    required int pwm,
    bool active = true,
    int? index,
  }) async =>
      acknowledgeWrites;

  @override
  Future<bool> removeSchedule(int index) async => acknowledgeWrites;
}
