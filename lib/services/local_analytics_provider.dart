import 'package:flutter/foundation.dart';
import 'local_db.dart';
import 'local_esp32_service.dart';

class SensorHistoryPoint {
  final double? ph;
  final double? ammonia;
  final double? turbidity;
  final double? waterTempC;
  final double? ambientTempC;
  final DateTime recordedAt;

  const SensorHistoryPoint({
    required this.ph, required this.ammonia, required this.turbidity,
    required this.waterTempC, required this.ambientTempC, required this.recordedAt,
  });

  factory SensorHistoryPoint.fromMap(Map<String, dynamic> m) => SensorHistoryPoint(
    ph: m['ph'] as double?,
    ammonia: m['ammonia'] as double?,
    turbidity: m['turbidity'] as double?,
    waterTempC: m['water_temp_c'] as double?,
    ambientTempC: m['ambient_temp_c'] as double?,
    recordedAt: DateTime.parse(m['recorded_at'] as String),
  );
}

/// Logs a sensor snapshot to SQLite roughly once a minute (not on every
/// reading the device pushes — that would make the history table
/// enormous for no real analytical benefit) and serves trend queries
/// for the Analytics tab's charts.
class LocalAnalyticsProvider extends ChangeNotifier {
  List<SensorHistoryPoint> history = [];
  bool isLoading = false;
  DateTime? _lastLoggedMinute;

  Future<void> maybeLogReading(LocalEsp32Service esp32) async {
    if (esp32.state != Esp32ConnectionState.connected) return;
    final now = DateTime.now();
    final currentMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    if (_lastLoggedMinute == currentMinute) return;
    _lastLoggedMinute = currentMinute;

    final db = await LocalDb.instance.database;
    await db.insert('sensor_history', {
      'ph': esp32.ph,
      'ammonia': esp32.ammonia,
      'turbidity': esp32.turbidity,
      'water_temp_c': esp32.waterTempC,
      'ambient_temp_c': esp32.ambientTempC,
      'fan_active': esp32.fanActive ? 1 : 0,
      'recorded_at': now.toIso8601String(),
      'synced_to_firebase': 0,
    });
  }

  /// [hoursBack] controls the chart window - 24 for a day view, 168
  /// for a week, etc.
  Future<void> fetchHistory({int hoursBack = 24}) async {
    isLoading = true;
    notifyListeners();
    final db = await LocalDb.instance.database;
    final cutoff = DateTime.now().subtract(Duration(hours: hoursBack)).toIso8601String();
    final rows = await db.query(
      'sensor_history',
      where: 'recorded_at >= ?',
      whereArgs: [cutoff],
      orderBy: 'recorded_at ASC',
    );
    history = rows.map(SensorHistoryPoint.fromMap).toList();
    isLoading = false;
    notifyListeners();
  }

  /// Leftover from the Firebase build, where the phone relayed history
  /// to the cloud. Nothing calls these two now: the ESP32 writes every
  /// reading to Supabase itself, so there is no backlog to upload.
  /// Kept because the column they read still exists (see [LocalDb]).
  Future<List<Map<String, dynamic>>> getUnsyncedBatch({int limit = 200}) async {
    final db = await LocalDb.instance.database;
    return db.query('sensor_history', where: 'synced_to_firebase = 0', orderBy: 'recorded_at ASC', limit: limit);
  }

  Future<void> markSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await LocalDb.instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.update('sensor_history', {'synced_to_firebase': 1}, where: 'id IN ($placeholders)', whereArgs: ids);
  }
}
