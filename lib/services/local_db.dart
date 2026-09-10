import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Per the move to a fully offline app: this is the app's own local
/// database now, living entirely on the phone. There is no server to
/// sync with - feeding schedules and notification history exist only
/// on this device, matching the same "fully offline" spirit as the
/// ESP32 connection itself.
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
      version: 2,
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Existing installs (version 1) never had sensor_history -
        // add it without touching feeding_schedules/notifications,
        // whose data should survive the upgrade untouched.
        if (oldVersion < 2) {
          await _createSensorHistoryTable(db);
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
}
