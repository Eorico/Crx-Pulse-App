import 'package:flutter_test/flutter_test.dart';
import 'package:crx_pulse/services/reading_cache.dart';

void main() {
  final t = DateTime(2026, 11, 2, 14, 30, 5);

  CachedReading sample({DateTime? at}) => CachedReading(
        ph: 7.24,
        ammonia: 0.17,
        turbidity: 42.5,
        turbidityStatus: 'Slightly Turbid',
        waterTempC: 26.4,
        ambientTempC: 31.2,
        fanActive: true,
        fanDutyPercent: 68,
        recordedAt: at ?? t,
      );

  group('CachedReading row mapping', () {
    test('survives a round trip through the row format', () {
      final r = CachedReading.fromRow(sample().toRow());

      expect(r, isNotNull);
      expect(r!.ph, 7.24);
      expect(r.ammonia, 0.17);
      expect(r.turbidity, 42.5);
      expect(r.turbidityStatus, 'Slightly Turbid');
      expect(r.waterTempC, 26.4);
      expect(r.ambientTempC, 31.2);
      expect(r.fanActive, isTrue);
      expect(r.fanDutyPercent, 68);
      expect(r.recordedAt, t);
    });

    test('always writes to the single row id = 1', () {
      // The table has CHECK (id = 1); a different id would make the
      // insert fail and silently stop caching.
      expect(sample().toRow()['id'], 1);
    });

    test('booleans cross SQLite as integers', () {
      expect(sample().toRow()['fan_active'], 1);
      final off = CachedReading(
        ph: null, ammonia: null, turbidity: null, turbidityStatus: null,
        waterTempC: null, ambientTempC: null,
        fanActive: false, fanDutyPercent: 0, recordedAt: t,
      );
      expect(off.toRow()['fan_active'], 0);
      expect(CachedReading.fromRow(off.toRow())!.fanActive, isFalse);
    });

    test('keeps nulls null rather than turning them into zeroes', () {
      // A sensor the firmware flagged invalid arrives as null, and the
      // UI shows "Not Connected" for null. Coercing it to 0.0 would
      // display a fabricated reading instead.
      final invalid = CachedReading(
        ph: null, ammonia: null, turbidity: null, turbidityStatus: null,
        waterTempC: 26.0, ambientTempC: null,
        fanActive: false, fanDutyPercent: 0, recordedAt: t,
      );
      final back = CachedReading.fromRow(invalid.toRow())!;

      expect(back.ph, isNull);
      expect(back.ammonia, isNull);
      expect(back.turbidity, isNull);
      expect(back.ambientTempC, isNull);
      expect(back.waterTempC, 26.0);
    });

    test('accepts integer-valued numbers from the row', () {
      // sqflite hands back whatever type the column holds; a pH stored
      // as exactly 7 can come back as an int, and a plain `as double?`
      // cast would throw on it.
      final row = sample().toRow()
        ..['ph'] = 7
        ..['fan_percent'] = 100;
      final r = CachedReading.fromRow(row);

      expect(r, isNotNull);
      expect(r!.ph, 7.0);
      expect(r.fanDutyPercent, 100);
    });

    test('rejects a row with no usable timestamp', () {
      // Without a time there is no way to judge the reading's age, and
      // the restore path depends on that to honour the freshness rule.
      expect(CachedReading.fromRow({...sample().toRow(), 'recorded_at': null}),
          isNull);
      expect(CachedReading.fromRow({...sample().toRow(), 'recorded_at': 'not a date'}),
          isNull);
    });
  });
}
