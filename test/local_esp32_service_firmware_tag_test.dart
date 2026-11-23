import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:crx_pulse/services/local_esp32_service.dart';

/// The service is a singleton that survives sign-out. A build tag belongs
/// to one board, so it must not outlive the session that read it — the
/// next sign-in may pair a different board, or one on older firmware.
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

  test('stopPolling clears the build tag from the previous device', () {
    final service = LocalEsp32Service();
    addTearDown(service.dispose);
    service.firmwareBuildTag = '2026.11.23-motor-first';

    service.stopPolling();

    expect(service.firmwareBuildTag, isNull);
  });
}
