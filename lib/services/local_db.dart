import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'offline_reading_store.dart';

/// The app's on-device database.
///
/// In the Supabase build this holds only what is genuinely local to
/// this phone: the notification history (alerts are evaluated here from
/// live readings) and the sensor history the Analytics tab charts.
///
/// Feeding schedules are NOT stored here any more — they live in
/// Supabase, because the ESP32 has to be able to read them itself. The
/// `feeding_schedules` table below is kept so an upgrade from an older
/// install does not drop data, but nothing writes to it.
///
/// Likewise `sensor_history.synced_to_firebase` is a leftover column
/// name from the Firebase build. Renaming it would need a migration for
/// no behavioural gain, so it stays; nothing reads or writes it, because
/// the device writes to the cloud directly.
///
/// The one thing this phone does upload is `offline_readings`: readings
/// taken straight off the device's own WiFi while there was no internet.
/// That is a separate table rather than a revival of the flag above —
/// those rows have to carry a full `readings` row, device_id and
/// validity flags included, which `sensor_history` has no columns for.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();
  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'crx_pulse_local.db');
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE feeding_schedules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            time TEXT NOT NULL,
            amount_grams REAL NOT NULL,
            zone TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            message TEXT NOT NULL,
            severity TEXT NOT NULL,
            created_at TEXT NOT NULL,
            read INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await _createSensorHistoryTable(db);
        await _createReadingCacheTable(db);
        await _createOfflineReadingsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Existing installs (version 1) never had sensor_history -
        // add it without touching feeding_schedules/notifications,
        // whose data should survive the upgrade untouched.
        if (oldVersion < 2) {
          await _createSensorHistoryTable(db);
        }
        if (oldVersion < 3) {
          await _createReadingCacheTable(db);
        }
        if (oldVersion < 4) {
          await _createOfflineReadingsTable(db);
        }
      },
    );
  }

  Future<void> _createSensorHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE sensor_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ph REAL,
        ammonia REAL,
        turbidity REAL,
        water_temp_c REAL,
        ambient_temp_c REAL,
        fan_active INTEGER,
        recorded_at TEXT NOT NULL,
        synced_to_firebase INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // Analytics queries filter/sort by time constantly - this index
    // keeps that fast even once history grows to thousands of rows.
    await db.execute('CREATE INDEX idx_sensor_history_recorded_at ON sensor_history(recorded_at)');
  }

  /// The last reading the device sent, kept so the dashboard has
  /// something to draw the instant it opens.
  ///
  /// Exactly one row, id = 1, replaced in place. This is a cache, not
  /// history - `sensor_history` is the history, and it only samples
  /// once a minute. Separate table rather than "newest row of
  /// sensor_history" because the two have different jobs: this one must
  /// hold the very latest values even between history samples, and
  /// reading it must be a single primary-key lookup on app start.
  /// Readings captured off the device's own WiFi while this phone had no
  /// internet, waiting to be pushed to Supabase.
  ///
  /// Owned by [OfflineReadingStore], which holds the DDL next to the
  /// code that reads and writes it; this class only decides when it
  /// comes into existence.
  Future<void> _createOfflineReadingsTable(Database db) async {
    await db.execute(OfflineReadingStore.createSql);
    await db.execute(OfflineReadingStore.createIndexSql);
  }

  Future<void> _createReadingCacheTable(Database db) async {
    await db.execute('''
      CREATE TABLE reading_cache (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        ph REAL,
        ammonia REAL,
        turbidity REAL,
        turbidity_status TEXT,
        water_temp_c REAL,
        ambient_temp_c REAL,
        fan_active INTEGER,
        fan_percent INTEGER,
        recorded_at TEXT NOT NULL
      )
    ''');
  }
}
