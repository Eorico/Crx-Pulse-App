import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'local_db.dart';

/// The last reading the device sent, as held on this phone.
@immutable
class CachedReading {
  final double? ph;
  final double? ammonia;
  final double? turbidity;
  final String? turbidityStatus;
  final double? waterTempC;
  final double? ambientTempC;
  final bool fanActive;
  final int fanDutyPercent;

  /// When the DEVICE recorded it, not when this phone stored it.
  final DateTime recordedAt;

  const CachedReading({
    required this.ph,
    required this.ammonia,
    required this.turbidity,
    required this.turbidityStatus,
    required this.waterTempC,
    required this.ambientTempC,
    required this.fanActive,
    required this.fanDutyPercent,
    required this.recordedAt,
  });

  Map<String, Object?> toRow() => {
        'id': 1,
        'ph': ph,
        'ammonia': ammonia,
        'turbidity': turbidity,
        'turbidity_status': turbidityStatus,
        'water_temp_c': waterTempC,
        'ambient_temp_c': ambientTempC,
        'fan_active': fanActive ? 1 : 0,
        'fan_percent': fanDutyPercent,
        'recorded_at': recordedAt.toIso8601String(),
      };

  static CachedReading? fromRow(Map<String, Object?> r) {
    final ts = r['recorded_at'];
    final at = ts is String ? DateTime.tryParse(ts) : null;
    if (at == null) return null;
    double? n(String k) => (r[k] as num?)?.toDouble();
    return CachedReading(
      ph: n('ph'),
      ammonia: n('ammonia'),
      turbidity: n('turbidity'),
      turbidityStatus: r['turbidity_status'] as String?,
      waterTempC: n('water_temp_c'),
      ambientTempC: n('ambient_temp_c'),
      fanActive: (r['fan_active'] as int? ?? 0) == 1,
      fanDutyPercent: (r['fan_percent'] as num?)?.toInt() ?? 0,
      recordedAt: at.toLocal(),
    );
  }
}

/// Stores and restores the most recent reading.
///
/// Why this exists: the app can only get readings through Supabase —
/// the firmware has no local HTTP endpoint — so on a cold start the
/// dashboard has nothing to show until the device resolves, the
/// subscription opens and the first row arrives. That gap is the pause
/// you see when opening the app. Painting the last known values
/// immediately removes it.
///
/// What it deliberately does NOT do: make readings fresher. A cache can
/// only ever replay what the device already sent. How current those
/// values are is set by the firmware's publish interval, and the cached
/// values are always labelled with their age so they are never mistaken
/// for live ones.
class ReadingCache {
  const ReadingCache();

  Future<CachedReading?> load() async {
    try {
      final db = await LocalDb.instance.database;
      final rows = await db.query('reading_cache', where: 'id = 1', limit: 1);
      if (rows.isEmpty) return null;
      return CachedReading.fromRow(rows.first);
    } catch (_) {
      // A cache miss must never break startup — if the table is not
      // there yet, or the row is unreadable, the app simply starts
      // blank the way it did before.
      return null;
    }
  }

  Future<void> save(CachedReading r) async {
    try {
      final db = await LocalDb.instance.database;
      await db.insert(
        'reading_cache',
        r.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Losing a cache write costs nothing but the next cold start.
    }
  }

  Future<void> clear() async {
    try {
      final db = await LocalDb.instance.database;
      await db.delete('reading_cache');
    } catch (_) {/* nothing to clean up */}
  }
}
