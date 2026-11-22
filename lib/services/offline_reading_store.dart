import 'dart:math';

import 'local_db.dart';

/// Readings taken straight off the device's own WiFi while there was no
/// internet, waiting to be pushed to Supabase.
///
/// The table mirrors a `readings` row column for column, so a buffered
/// row needs no translation on the way up — it is inserted exactly as
/// the device would have inserted it, and the Analytics tab cannot tell
/// the difference afterwards.
///
/// Two deliberate choices:
///
/// * **The id is generated here, not by Postgres.** `readings.id` has a
///   `gen_random_uuid()` default, so the obvious thing is to let the
///   server assign it. But then a push that reaches the database and
///   whose *response* is lost — exactly what a flaky reconnection
///   produces — cannot be retried safely, because the retry looks like
///   a brand new row. Carrying our own uuid makes the push idempotent:
///   the retry collides on the primary key and is ignored.
///
/// * **`recorded_at` is stamped by the phone.** The device has no
///   trustworthy clock while it is offline (NTP needs internet), so the
///   firmware deliberately sends no timestamp. The phone's clock is the
///   only real one in the room.
class OfflineReadingStore {
  const OfflineReadingStore();

  static const String table = 'offline_readings';

  /// Ceiling on the buffer, oldest discarded first.
  ///
  /// At one reading every three seconds this is a little over 16 hours
  /// of continuous offline capture. The cap exists so a phone left on
  /// the tank's own WiFi for a week cannot grow the database without
  /// limit; losing the oldest readings is the right thing to lose.
  static const int maxRows = 20000;

  /// The `readings` columns this buffer carries, in insert order.
  ///
  /// Public because it IS the contract: a buffered row is pushed to
  /// Supabase verbatim, so this list has to be the `readings` table's
  /// columns minus `id`, which the buffer adds itself. Verified against
  /// supabase_schema.sql and against the firmware's localReadingJson()
  /// in offline_reading_store_test.dart.
  static const List<String> columns = [
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

  /// Columns SQLite has to hold as INTEGER because it has no boolean
  /// type, and that Postgres wants back as real booleans.
  static const Set<String> boolColumns = {
    'fan_active',
    'ph_valid',
    'turbidity_valid',
    'water_temp_valid',
    'ambient_valid',
    'ammonia_valid',
  };

  static const String createSql = '''
    CREATE TABLE $table (
      id               TEXT PRIMARY KEY,
      device_id        TEXT NOT NULL,
      ph               REAL,
      ammonia          REAL,
      turbidity        REAL,
      turbidity_status TEXT,
      water_temp_c     REAL,
      ambient_temp_c   REAL,
      fan_active       INTEGER,
      fan_percent      INTEGER,
      ph_valid         INTEGER,
      turbidity_valid  INTEGER,
      water_temp_valid INTEGER,
      ambient_valid    INTEGER,
      ammonia_valid    INTEGER,
      recorded_at      TEXT NOT NULL
    )
  ''';

  static const String createIndexSql =
      'CREATE INDEX idx_${table}_recorded_at ON $table(recorded_at)';

  /// Buffers one reading. [reading] uses the `readings` column names,
  /// which is what the device's `/api/live` already returns.
  ///
  /// Returns the number of rows waiting afterwards, so the caller can
  /// show a queue depth without a second query.
  Future<int> add(Map<String, dynamic> reading) async {
    final db = await LocalDb.instance.database;

    await db.insert(table, rowForBuffer(reading));

    final total = await count();
    if (total > maxRows) {
      // Drop the oldest overflow in one statement rather than row by
      // row: this runs on a phone, under a timer, while the tank is
      // being read.
      await db.rawDelete('''
        DELETE FROM $table WHERE id IN (
          SELECT id FROM $table ORDER BY recorded_at ASC, id ASC LIMIT ?
        )
      ''', [total - maxRows]);
      return maxRows;
    }
    return total;
  }

  /// The oldest buffered readings, shaped for a Supabase insert:
  /// booleans as booleans, nulls preserved, `id` included.
  ///
  /// Oldest first so the cloud receives them in the order they were
  /// taken, which is the order the charts want.
  Future<List<Map<String, dynamic>>> nextBatch({int limit = 200}) async {
    final db = await LocalDb.instance.database;
    final rows = await db.query(
      table,
      orderBy: 'recorded_at ASC, id ASC',
      limit: limit,
    );
    return rows.map(rowForCloud).toList();
  }

  Future<void> remove(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final db = await LocalDb.instance.database;
    final marks = List.filled(list.length, '?').join(',');
    await db.rawDelete('DELETE FROM $table WHERE id IN ($marks)', list);
  }

  Future<int> count() async {
    final db = await LocalDb.instance.database;
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return (r.first['n'] as int?) ?? 0;
  }

  Future<void> clear() async {
    final db = await LocalDb.instance.database;
    await db.delete(table);
  }

  /// Turns a buffered SQLite row into the row Supabase is given:
  /// INTEGER flags back into booleans, nulls preserved, `id` first.
  static Map<String, dynamic> rowForCloud(Map<String, Object?> row) {
    final out = <String, dynamic>{'id': row['id']};
    for (final c in columns) {
      final v = row[c];
      out[c] = boolColumns.contains(c) ? _toBool(v) : v;
    }
    return out;
  }

  /// Turns a reading as the device's /api/live sends it into the row
  /// this table stores. Exposed so the mapping can be checked without a
  /// database.
  static Map<String, Object?> rowForBuffer(Map<String, dynamic> reading,
      {String? id}) {
    final row = <String, Object?>{'id': id ?? newId()};
    for (final c in columns) {
      final v = reading[c];
      row[c] = boolColumns.contains(c) ? _toInt(v) : v;
    }
    return row;
  }

  static int? _toInt(Object? v) {
    if (v == null) return null;
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v == 0 ? 0 : 1;
    return null;
  }

  static bool? _toBool(Object? v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    return null;
  }

  static final Random _rng = Random.secure();

  /// A version-4 UUID, in the text form Postgres accepts for a `uuid`
  /// column. Hand-rolled rather than adding a package for sixteen
  /// random bytes.
  static String newId() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant 1
    String hex(int from, int to) => [
          for (var i = from; i < to; i++) b[i].toRadixString(16).padLeft(2, '0')
        ].join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
