import 'package:flutter_test/flutter_test.dart';
import 'package:crx_pulse/core/firmware_spec.dart';
import 'package:crx_pulse/core/metric_bands.dart';

/// The zone closures exactly as the analytics screen carried them
/// before they became [MetricBands] data. Kept here so the refactor can
/// be proven behaviour-preserving rather than assumed to be: a band
/// that disagrees at a boundary would silently misfile readings into
/// the wrong zone, and nothing on screen would look broken.
int _oldPh(double v) =>
    v < FirmwareSpec.phSafeMin ? 0 : (v <= FirmwareSpec.phSafeMax ? 1 : 2);

int _oldAmmonia(double v) => v < FirmwareSpec.ammoniaSafeMax
    ? 0
    : (v < FirmwareSpec.ammoniaWarningMax ? 1 : 2);

int _oldTurbidity(double v) => v <= FirmwareSpec.turbidityClearMax
    ? 0
    : (v <= FirmwareSpec.turbiditySlightlyMax
        ? 1
        : (v <= FirmwareSpec.turbidityTurbidMax ? 2 : 3));

int _oldWaterTemp(double v) => v < FirmwareSpec.waterTempSafeMinC
    ? 0
    : (v <= FirmwareSpec.waterTempSafeMaxC ? 1 : 2);

int _oldHousing(double v) => v < FirmwareSpec.coolingStartC
    ? 0
    : (v < FirmwareSpec.coolingMaxC ? 1 : 2);

void main() {
  const ph = MetricBands(
    column: 'ph',
    cuts: [FirmwareSpec.phSafeMin, FirmwareSpec.phSafeMax],
    strict: [true, false],
  );
  const ammonia = MetricBands(
    column: 'ammonia',
    cuts: [FirmwareSpec.ammoniaSafeMax, FirmwareSpec.ammoniaWarningMax],
    strict: [true, true],
  );
  const turbidity = MetricBands(
    column: 'turbidity',
    cuts: [
      FirmwareSpec.turbidityClearMax,
      FirmwareSpec.turbiditySlightlyMax,
      FirmwareSpec.turbidityTurbidMax,
    ],
    strict: [false, false, false],
  );
  const waterTemp = MetricBands(
    column: 'water_temp_c',
    cuts: [FirmwareSpec.waterTempSafeMinC, FirmwareSpec.waterTempSafeMaxC],
    strict: [true, false],
  );
  const housing = MetricBands(
    column: 'ambient_temp_c',
    cuts: [FirmwareSpec.coolingStartC, FirmwareSpec.coolingMaxC],
    strict: [true, true],
  );

  /// Sweeps the range AND lands exactly on every cut, plus one step
  /// either side — boundaries are where a wrong operator shows up, and
  /// the firmware reports to 1–2 decimals so exact hits are common.
  void agreesWith(MetricBands b, int Function(double) old,
      {required double from, required double to}) {
    final probes = <double>[
      for (double v = from; v <= to; v += (to - from) / 400) v,
      for (final c in b.cuts) ...[c, c - 1e-9, c + 1e-9, c - 0.01, c + 0.01],
      from - 50, to + 50,
    ];
    for (final v in probes) {
      expect(b.zoneOf(v), old(v),
          reason: 'zone disagreement at $v for ${b.column}');
    }
  }

  group('MetricBands reproduces the original zone closures', () {
    test('pH', () => agreesWith(ph, _oldPh, from: 0, to: 14));
    test('ammonia', () => agreesWith(ammonia, _oldAmmonia, from: 0, to: 2));
    test('turbidity',
        () => agreesWith(turbidity, _oldTurbidity, from: 0, to: 100));
    test('water temperature',
        () => agreesWith(waterTemp, _oldWaterTemp, from: 0, to: 50));
    test('housing temperature',
        () => agreesWith(housing, _oldHousing, from: 0, to: 60));
  });

  group('boundary semantics are the ones the bands claim', () {
    test('pH 6.5 is Optimal, not Low — the cut is strict', () {
      expect(ph.zoneOf(FirmwareSpec.phSafeMin), 1);
      expect(ph.zoneOf(FirmwareSpec.phSafeMin - 0.01), 0);
    });

    test('pH 8.5 is Optimal, not High — the cut is inclusive', () {
      expect(ph.zoneOf(FirmwareSpec.phSafeMax), 1);
      expect(ph.zoneOf(FirmwareSpec.phSafeMax + 0.01), 2);
    });

    test('turbidity 19.9% is Clear — every cut is the top of its band', () {
      // 1.33015 V maps to 19.9 % and is still Clear, so the first cut is
      // inclusive like the other two.
      expect(turbidity.zoneOf(FirmwareSpec.turbidityClearMax), 0);
      expect(turbidity.zoneOf(FirmwareSpec.turbidityClearMax + 0.01), 1);
      expect(turbidity.zoneOf(FirmwareSpec.turbiditySlightlyMax), 1);
      expect(turbidity.zoneOf(FirmwareSpec.turbiditySlightlyMax + 0.01), 2);
      expect(turbidity.zoneOf(FirmwareSpec.turbidityTurbidMax), 2);
      expect(turbidity.zoneOf(FirmwareSpec.turbidityTurbidMax + 0.01), 3);
      expect(turbidity.zoneOf(100), 3);
    });

    test('ammonia 0.25 is already Warning — both cuts strict', () {
      expect(ammonia.zoneOf(FirmwareSpec.ammoniaSafeMax), 1);
      expect(ammonia.zoneOf(FirmwareSpec.ammoniaWarningMax), 2);
    });
  });

  group('shape', () {
    test('zoneCount is one more than the number of cuts', () {
      expect(ph.zoneCount, 3);
      expect(turbidity.zoneCount, 4);
    });

    test('cuts and strict stay the same length', () {
      for (final b in [ph, ammonia, turbidity, waterTemp, housing]) {
        expect(b.strict.length, b.cuts.length, reason: b.column);
      }
    });

    test('cuts are ascending, as the SQL function requires', () {
      for (final b in [ph, ammonia, turbidity, waterTemp, housing]) {
        for (int i = 1; i < b.cuts.length; i++) {
          expect(b.cuts[i], greaterThan(b.cuts[i - 1]), reason: b.column);
        }
      }
    });
  });
}
