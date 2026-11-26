import 'package:flutter_test/flutter_test.dart';
import 'package:crx_pulse/core/firmware_spec.dart';

/// Pins the standard turbidity table and the explicit pH buffers.
///
/// The reference percentages below were produced by running the same
/// five-point curve that ships in `TurbidityCalibration::percentOf` on
/// the host. If the app's copy of the curve ever drifts from the
/// firmware's, these fail — the device sends a percentage, so a
/// disagreement between the two would otherwise be invisible on screen.
void main() {
  group('turbidity curve matches the firmware', () {
    // (pin volts, percent) from the compiled firmware curve.
    const reference = <(double, double)>[
      (0.0000, 100.000000),
      (0.9667, 100.000000),
      (1.1916, 100.000000),
      (1.2000, 95.148178),
      (1.22865, 78.600000),
      (1.2500, 66.241635),
      (1.28065, 48.500000),
      (1.3000, 37.320000),
      (1.33015, 19.900000),
      (1.3500, 8.433672),
      (1.3646, 0.000000),
      (1.3960, 0.000000),
      (1.4040, 0.000000),
      (1.5000, 0.000000),
      (3.3000, 0.000000),
    ];

    // The firmware computes in float and Dart in double. The steepest
    // segment is about 580 %/V, so a 1e-7 V rounding difference becomes
    // a negligible fraction of a percent.
    test('every reference point agrees with the firmware', () {
      for (final (volts, expected) in reference) {
        expect(FirmwareSpec.turbidityPercentOf(volts), closeTo(expected, 0.005),
            reason: 'at $volts V');
      }
    });

    test('and classifies every reference point the same way', () {
      const bandOf = FirmwareSpec.turbidityStatusOf;
      for (final (volts, expected) in reference) {
        expect(bandOf(FirmwareSpec.turbidityPercentOf(volts)), bandOf(expected),
            reason: 'at $volts V');
      }
    });

    test('the standard anchors land on 0 / 19.9 / 48.5 / 78.6 / 100 %', () {
      expect(FirmwareSpec.turbidityPercentOf(1.36460), closeTo(0.0, 1e-6));
      expect(FirmwareSpec.turbidityPercentOf(1.33015), closeTo(19.9, 1e-6));
      expect(FirmwareSpec.turbidityPercentOf(1.28065), closeTo(48.5, 1e-6));
      expect(FirmwareSpec.turbidityPercentOf(1.22865), closeTo(78.6, 1e-6));
      expect(FirmwareSpec.turbidityPercentOf(1.19160), closeTo(100.0, 1e-6));
    });

    test('the reported clear readings are Clear at 0 %', () {
      // The two ADC values from the serial log that the old 1.770/1.724 V
      // curve saturated at 100 %. They are above the 0 % endpoint now.
      for (final volts in [1.396, 1.404]) {
        expect(FirmwareSpec.turbidityPercentOf(volts), 0.0,
            reason: 'at $volts V');
        expect(
            FirmwareSpec.turbidityStatusOf(
                FirmwareSpec.turbidityPercentOf(volts)),
            'Clear',
            reason: 'at $volts V');
      }
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
      expect(FirmwareSpec.turbidityPercentOf(3.3), 0.0);
      expect(FirmwareSpec.turbidityPercentOf(0.0), 100.0);
    });
  });

  group('turbidity bands are the stated standard', () {
    test('edges are exactly 19.9 / 48.5 / 78.6', () {
      expect(FirmwareSpec.turbidityClearMax, 19.9);
      expect(FirmwareSpec.turbiditySlightlyMax, 48.5);
      expect(FirmwareSpec.turbidityTurbidMax, 78.6);
    });

    test('each upper edge belongs to the band that names it', () {
      expect(FirmwareSpec.turbidityStatusOf(0.0), 'Clear');
      expect(FirmwareSpec.turbidityStatusOf(19.9), 'Clear');
      expect(FirmwareSpec.turbidityStatusOf(19.9001), 'Slightly Turbid');
      expect(FirmwareSpec.turbidityStatusOf(48.5), 'Slightly Turbid');
      expect(FirmwareSpec.turbidityStatusOf(48.5001), 'Turbid');
      expect(FirmwareSpec.turbidityStatusOf(78.6), 'Turbid');
      expect(FirmwareSpec.turbidityStatusOf(78.6001), 'Highly Turbid');
      expect(FirmwareSpec.turbidityStatusOf(100.0), 'Highly Turbid');
    });

    test('voltage thresholds land on those exact band edges', () {
      const edges = <(double, String)>[
        (1.3960, 'Clear'),
        (1.33015, 'Clear'),
        (1.3200, 'Slightly Turbid'),
        (1.28065, 'Slightly Turbid'),
        (1.2500, 'Turbid'),
        (1.22865, 'Turbid'),
        (1.2000, 'Highly Turbid'),
      ];
      for (final (volts, band) in edges) {
        expect(
            FirmwareSpec.turbidityStatusOf(
                FirmwareSpec.turbidityPercentOf(volts)),
            band,
            reason: 'at $volts V');
      }
    });
  });

  group('pH calibration reference', () {
    test('records the explicit standard buffers', () {
      expect(FirmwareSpec.phBufferNeutral, 6.86);
      expect(FirmwareSpec.phBufferAcid, 4.01);
      expect(FirmwareSpec.phBufferBase, 9.18);
    });

    test('anchor voltages are the specified buffer voltages', () {
      expect(FirmwareSpec.phVoltNeutral, closeTo(1.950, 1e-9));
      expect(FirmwareSpec.phVoltAcid, closeTo(2.447, 1e-9));
      expect(FirmwareSpec.phVoltBase, closeTo(1.425, 1e-9));
    });

    test('voltage falls as pH rises, so the ordering is sane', () {
      expect(FirmwareSpec.phVoltAcid, greaterThan(FirmwareSpec.phVoltNeutral));
      expect(FirmwareSpec.phVoltNeutral, greaterThan(FirmwareSpec.phVoltBase));
    });

    test('all three buffers sit inside the app\'s alert range check', () {
      expect(FirmwareSpec.phIsSafe(FirmwareSpec.phBufferNeutral), isTrue);
      expect(FirmwareSpec.phIsSafe(FirmwareSpec.phBufferAcid), isFalse);
      expect(FirmwareSpec.phIsSafe(FirmwareSpec.phBufferBase), isFalse);
    });
  });
}
