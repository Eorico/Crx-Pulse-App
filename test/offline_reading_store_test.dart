import 'package:flutter_test/flutter_test.dart';
import 'package:crx_pulse/services/offline_reading_store.dart';

/// Pins the contract that makes the offline buffer work: a row captured
/// off the device's own WiFi is pushed to Supabase *verbatim*, so its
/// columns must be the `readings` table's columns, no more and no less.
///
/// A drift here would not look like a bug. The reading would appear on
/// the dashboard, be buffered, and then fail its insert — hours later,
/// out of sight, with the readings already taken.
void main() {
  /// `public.readings` as supabase_schema.sql declares it, in order.
  /// Copied from the schema, not derived from the code under test.
  const schemaColumns = <String>[
    'id',
    'device_id',
    'ph',
    'ammonia',
    'turbidity',
    'turbidity_status',
    'water_temp_c',
    'ambient_temp_c',
    'fan_active',
    'fan_percent',
    'ph_valid',
    'turbidity_valid',
    'water_temp_valid',
    'ambient_valid',
    'ammonia_valid',
    'recorded_at',
  ];

  /// What the firmware's localReadingJson() sends, verbatim — every key
  /// it sets, with the JSON types ArduinoJson produces. Note what is
  /// absent: no `id`, no `recorded_at`. The device has no trustworthy
  /// clock while it is offline, so it deliberately sends no timestamp.
  Map<String, dynamic> firmwarePayload() => {
        'device_id': 'CRX-PULSE-01',
        'ph': 7.24,
        'ammonia': 0.17,
        'turbidity': 42.5,
        'turbidity_status': 'Slightly Turbid',
        'water_temp_c': 26.4,
        'ambient_temp_c': 31.2,
        'fan_active': true,
        'fan_percent': 68,
        'ph_valid': true,
        'turbidity_valid': true,
        'water_temp_valid': true,
        'ambient_valid': true,
        'ammonia_valid': false,
      };

  group('the buffer carries a whole readings row', () {
    test('its columns are the readings table minus the id it adds', () {
      expect(OfflineReadingStore.columns,
          schemaColumns.where((c) => c != 'id').toList());
    });

    test('and the SQL that creates it declares exactly those columns', () {
      // Catches a column added to `columns` but not to the DDL, which
      // SQLite would only report at insert time.
      for (final c in ['id', ...OfflineReadingStore.columns]) {
        expect(OfflineReadingStore.createSql, contains(c),
            reason: '$c missing from createSql');
      }
    });

    test('every flag the firmware sends as a bool is stored as INTEGER', () {
      // SQLite has no boolean. Any key the firmware sends as true/false
      // has to be in boolColumns or it round-trips as a 1 or a 0 and
      // Postgres rejects the insert.
      final boolKeys = firmwarePayload()
          .entries
          .where((e) => e.value is bool)
          .map((e) => e.key)
          .toSet();
      expect(OfflineReadingStore.boolColumns, boolKeys);
    });
  });

  group('mapping a reading into the buffer and back out', () {
    test('a firmware payload keeps every value through the round trip', () {
      final payload = firmwarePayload();
      final buffered = OfflineReadingStore.rowForBuffer(payload, id: 'fixed-id');
      final cloud = OfflineReadingStore.rowForCloud(buffered);

      expect(cloud['id'], 'fixed-id');
      for (final e in payload.entries) {
        expect(cloud[e.key], e.value, reason: e.key);
      }
    });

    test('booleans become 1 and 0 on the way in', () {
      final row = OfflineReadingStore.rowForBuffer(firmwarePayload());
      expect(row['fan_active'], 1);
      expect(row['ammonia_valid'], 0);
      expect(row['ph_valid'], 1);
    });

    test('and come back out as booleans, not as 1 and 0', () {
      final cloud = OfflineReadingStore.rowForCloud(
          OfflineReadingStore.rowForBuffer(firmwarePayload()));
      expect(cloud['fan_active'], isA<bool>());
      expect(cloud['ammonia_valid'], false);
    });

    test('a key the firmware does not send is present and null', () {
      // recorded_at is stamped by the caller, but the row still has to
      // carry the column — a missing key in the batch would make
      // PostgREST fall back to the column default for every row.
      final row = OfflineReadingStore.rowForBuffer(firmwarePayload());
      expect(row.containsKey('recorded_at'), isTrue);
      expect(row['recorded_at'], isNull);
    });

    test('a null sensor stays null rather than becoming 0', () {
      // A sensor the firmware flagged invalid can arrive as null. Mapped
      // to 0 it would read as a real measurement of zero.
      final row = OfflineReadingStore.rowForBuffer({
        ...firmwarePayload(),
        'ph': null,
        'ph_valid': null,
      });
      expect(row['ph'], isNull);
      expect(row['ph_valid'], isNull);
      expect(OfflineReadingStore.rowForCloud(row)['ph_valid'], isNull);
    });

    test('an unknown key from a future firmware is dropped, not inserted', () {
      // If a new field went into the row unchanged, SQLite would answer
      // "no such column" and the reading would be lost at capture time.
      // Dropping it loses one field; keeping it loses the reading.
      final row = OfflineReadingStore.rowForBuffer({
        ...firmwarePayload(),
        'dissolved_oxygen': 8.1,
      });
      expect(row.containsKey('dissolved_oxygen'), isFalse);
      expect(row.keys.toSet(), {'id', ...OfflineReadingStore.columns});
    });
  });

  group('the id the buffer assigns', () {
    test('is a version-4 uuid Postgres will accept', () {
      final id = OfflineReadingStore.newId();
      expect(
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
              .hasMatch(id),
          isTrue,
          reason: id);
    });

    test('is unique across a buffer-sized run', () {
      // The id is what makes a retried push idempotent. A collision
      // would silently discard a reading as a duplicate.
      final ids = {
        for (var i = 0; i < OfflineReadingStore.maxRows; i++)
          OfflineReadingStore.newId()
      };
      expect(ids.length, OfflineReadingStore.maxRows);
    });
  });
}
