import 'package:crx_pulse/core/firmware_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// /api/status is served by the ESP32's own WiFi, and older builds do not
/// carry a build tag. The parser is what lets the app show the new tag
/// without treating those older boards as strangers.
void main() {
  group('buildTagFromStatus', () {
    test('returns the tag the firmware sent', () {
      expect(
        buildTagFromStatus({'build_tag': '2026.11.23-motor-first'}),
        '2026.11.23-motor-first',
      );
    });

    test('trims whitespace around the tag', () {
      expect(
        buildTagFromStatus({'build_tag': '  2026.11.23-motor-first  '}),
        '2026.11.23-motor-first',
      );
    });

    test('returns null when the key is absent', () {
      expect(buildTagFromStatus({'firmware': '1.0.0'}), isNull);
    });

    test('returns null when the value is not a string', () {
      expect(buildTagFromStatus({'build_tag': 20261123}), isNull);
    });

    test('returns null when the value is empty after trimming', () {
      expect(buildTagFromStatus({'build_tag': '   '}), isNull);
    });
  });
}
