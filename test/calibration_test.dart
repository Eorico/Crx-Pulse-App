import 'package:flutter_test/flutter_test.dart';
import 'package:crx_pulse/core/firmware_spec.dart';

/// Pins the 2026-11-06 calibration.
///
/// The reference percentages below were produced by COMPILING AND
/// RUNNING `TurbidityCalibration::percentOf` out of crx_pulse.ino on
/// the host, not by re-deriving them here. If the app's copy of the
/// curve ever drifts from the firmware's, these fail — which is the
/// whole point, since the device sends a percentage the app then
/// classifies, and the two disagreeing would be invisible on screen.
void main() {
  group('turbidity curve matches the firmware', () {
    // (pin volts, percent) straight out of the compiled firmware class.
    const reference = <(double, double)>[
      (0.0000, 100.000000),
      (0.9667, 100.000000),
      (1.2000, 100.000000),
      (1.6810, 100.000000),
      (1.7200, 100.000000),
      (1.7240, 100.000000),
      (1.7250, 97.825986),
      (1.7300, 86.956432),
      (1.7339, 78.478319),
      (1.7400, 65.217324),
      (1.7477, 48.478268),
      (1.7500, 43.478216),
      (1.7608, 19.999948),
      (1.7650, 10.869554),
      (1.7699, 0.217427),
      (1.7700, 0.000000),
      (1.7741, 0.000000),
      (1.7959, 0.000000),
      (1.8120, 0.000000),
      (2.0000, 0.000000),
      (3.3000, 0.000000),
    ];

    // Tolerance is 0.005 %, not zero, because the firmware computes in
    // `float` and Dart in `double`. That only shows up on the
    // Clear -> Slightly segment, which is 2126 %/V — just 16.1 mV wide
    // carrying 34 percentage points — so a 1e-7 V rounding difference
    // becomes ~2e-4 %. At 1.800 V the two give 25.516871 and
    // 25.516770; both are "Slightly Turbid", and 0.0001 % of turbidity
    // has no physical meaning.
    test('every reference point agrees with the firmware', () {
      for (final (volts, expected) in reference) {
        expect(FirmwareSpec.turbidityPercentOf(volts), closeTo(expected, 0.005),
            reason: 'at $volts V');
      }
    });

    test('and classifies every reference point the same way', () {
      // The tolerance above must never be wide enough to let a band
      // disagreement through, so check the bands too.
      const bandOf = FirmwareSpec.turbidityStatusOf;
      for (final (volts, expected) in reference) {
        expect(bandOf(FirmwareSpec.turbidityPercentOf(volts)), bandOf(expected),
            reason: 'at $volts V');
      }
    });

    test('the two tank anchors return 0 % and 100 %', () {
      expect(FirmwareSpec.turbidityPercentOf(1.770), closeTo(0.0, 1e-6));
      expect(FirmwareSpec.turbidityPercentOf(1.724), closeTo(100.0, 1e-6));
    });

    test('1.770 V is Clear and 1.724 V is Highly Turbid', () {
      // The two points this calibration was built to satisfy.
      expect(
          FirmwareSpec.turbidityStatusOf(FirmwareSpec.turbidityPercentOf(1.770)),
          'Clear');
      expect(
          FirmwareSpec.turbidityStatusOf(FirmwareSpec.turbidityPercentOf(1.724)),
          'Highly Turbid');
    });

    test('is monotonic: more turbid water never reads as clearer', () {
      double? prev;
      for (double v = 2.0; v >= 0.5; v -= 0.001) {
        final p = FirmwareSpec.turbidityPercentOf(v);
        if (prev != null) {
          expect(p, greaterThanOrEqualTo(prev - 1e-9), reason: 'at $v V');
        }
        prev = p;
      }
    });

    test('flat outside the measured ends rather than extrapolating', () {
      // Beyond the calibrated span there is no data, so the curve must
      // clamp. Extrapolating would invent percentages below 0 or above
      // 100 from voltages the sensor was never characterised at.
      expect(FirmwareSpec.turbidityPercentOf(3.3), 0.0);
      expect(FirmwareSpec.turbidityPercentOf(0.0), 100.0);
    });
  });

  group('turbidity bands are the stated standard', () {
    test('edges are exactly 19.94 / 48.53 / 78.58', () {
      expect(FirmwareSpec.turbidityClearMax, 19.94);
      expect(FirmwareSpec.turbiditySlightlyMax, 48.53);
      expect(FirmwareSpec.turbidityTurbidMax, 78.58);
    });

    test('"Clear: 0 -< 19.94%" means 19.94 is already Slightly Turbid', () {
      expect(FirmwareSpec.turbidityStatusOf(0.0), 'Clear');
      expect(FirmwareSpec.turbidityStatusOf(19.93), 'Clear');
      expect(FirmwareSpec.turbidityStatusOf(19.94), 'Slightly Turbid');
      expect(FirmwareSpec.turbidityStatusOf(48.53), 'Slightly Turbid');
      expect(FirmwareSpec.turbidityStatusOf(48.54), 'Turbid');
      expect(FirmwareSpec.turbidityStatusOf(78.58), 'Turbid');
      expect(FirmwareSpec.turbidityStatusOf(78.59), 'Highly Turbid');
      expect(FirmwareSpec.turbidityStatusOf(100.0), 'Highly Turbid');
    });

    test('band edges fall at the expected voltages', () {
      // Derived from the two anchors: 46 mV carries the whole scale, so
      // each band is ~9-13 mV wide. Checked either side of each edge.
      const edges = <(double, String)>[
        (1.7650, 'Clear'),
        (1.7608, 'Slightly Turbid'),
        (1.7500, 'Slightly Turbid'),
        (1.7477, 'Slightly Turbid'),
        (1.7400, 'Turbid'),
        (1.7339, 'Turbid'),
        (1.7300, 'Highly Turbid'),
      ];
      for (final (volts, band) in edges) {
        expect(
            FirmwareSpec.turbidityStatusOf(
                FirmwareSpec.turbidityPercentOf(volts)),
            band,
            reason: 'at $volts V');
      }
    });

    test('everything outside the 46 mV window saturates', () {
      // Above the clear anchor, and below the turbid one, there is no
      // gradient left — which is the cost of this working range.
      for (final v in [1.7700, 1.7741, 1.7959, 1.8120, 2.0, 3.3]) {
        expect(FirmwareSpec.turbidityPercentOf(v), 0.0, reason: 'at $v V');
      }
      for (final v in [1.7240, 1.6810, 1.2, 0.9667, 0.0]) {
        expect(FirmwareSpec.turbidityPercentOf(v), 100.0, reason: 'at $v V');
      }
    });
  });

  group('pH calibration reference', () {
    test('records the real buffers, not 7.00 / 4.00', () {
      // The firmware formula used to hard-code 7.00 and 4.00 as its
      // anchors while the buffers in use are 6.78 and 4.05, which is
      // what made neutral read ~7.80.
      expect(FirmwareSpec.phBufferNeutral, 6.78);
      expect(FirmwareSpec.phBufferAcid, 4.05);
      expect(FirmwareSpec.phBufferBase, 9.18);
    });

    test('anchor voltages are the trimmed bench means', () {
      expect(FirmwareSpec.phVoltNeutral, closeTo(1.7567, 1e-9));
      expect(FirmwareSpec.phVoltAcid, closeTo(2.3891, 1e-9));
      expect(FirmwareSpec.phVoltBase, closeTo(1.2754, 1e-9));
    });

    test('voltage falls as pH rises, so the ordering is sane', () {
      expect(FirmwareSpec.phVoltAcid, greaterThan(FirmwareSpec.phVoltNeutral));
      expect(FirmwareSpec.phVoltNeutral, greaterThan(FirmwareSpec.phVoltBase));
    });

    test('all three buffers sit inside the app\'s alert range check', () {
      // 6.78 is safe; 4.05 and 9.18 are not. If this ever flips, the
      // dashboard would stop flagging an out-of-range tank.
      expect(FirmwareSpec.phIsSafe(FirmwareSpec.phBufferNeutral), isTrue);
      expect(FirmwareSpec.phIsSafe(FirmwareSpec.phBufferAcid), isFalse);
      expect(FirmwareSpec.phIsSafe(FirmwareSpec.phBufferBase), isFalse);
    });
  });
}
