import 'package:flutter/foundation.dart';
import 'local_db.dart';
import 'local_esp32_service.dart';

class FeedingSchedule {
  final int id;
  final String time;
  final double amountGrams;
  final String zone;
  final bool active;

  const FeedingSchedule({required this.id, required this.time, required this.amountGrams, required this.zone, required this.active});

  factory FeedingSchedule.fromMap(Map<String, dynamic> m) => FeedingSchedule(
    id: m['id'] as int,
    time: m['time'] as String,
    amountGrams: m['amount_grams'] as double,
    zone: m['zone'] as String,
    active: (m['active'] as int) == 1,
  );
}

/// Restores the original scheduling UI/functionality (times, zones,
/// per-schedule toggles) - the actual storage now lives in SQLite on
/// the phone rather than a backend database.
///
/// HONEST LIMITATION: this app cannot trigger feeding automatically
/// at a scheduled time while closed or backgrounded - Flutter apps
/// don't run code in the background without a separate native
/// scheduling integration (e.g. WorkManager), which is a much larger
/// addition. Schedules are stored and displayed exactly like before;
/// while the app is OPEN, it checks once a minute and will trigger a
/// due schedule automatically. For guaranteed feeding regardless of
/// whether the app is open, "Feed Now" from Management remains the
/// reliable path.
class LocalFeedingProvider extends ChangeNotifier {
  List<FeedingSchedule> schedules = [];
  bool isLoading = false;
  DateTime? _lastCheckedMinute;

  Future<void> fetchSchedules() async {
    isLoading = true;
    notifyListeners();
    final db = await LocalDb.instance.database;
    final rows = await db.query('feeding_schedules', orderBy: 'time ASC');
    schedules = rows.map(FeedingSchedule.fromMap).toList();
    isLoading = false;
    notifyListeners();
  }

  Future<void> createSchedule(String time, double amountGrams, String zone) async {
    final db = await LocalDb.instance.database;
    await db.insert('feeding_schedules', {'time': time, 'amount_grams': amountGrams, 'zone': zone, 'active': 1});
    await fetchSchedules();
  }

  Future<void> toggleSchedule(int id, bool active) async {
    final db = await LocalDb.instance.database;
    await db.update('feeding_schedules', {'active': active ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    await fetchSchedules();
  }

  Future<void> deleteSchedule(int id) async {
    final db = await LocalDb.instance.database;
    await db.delete('feeding_schedules', where: 'id = ?', whereArgs: [id]);
    await fetchSchedules();
  }

  /// Called periodically (once a minute) while the app is open -
  /// checks whether any active schedule matches the current time and
  /// triggers the ESP32's real feed action if so. This is the "best
  /// effort while open" behavior described above.
  Future<void> checkDueSchedules(LocalEsp32Service esp32) async {
    final now = DateTime.now();
    final currentMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    if (_lastCheckedMinute == currentMinute) return;
    _lastCheckedMinute = currentMinute;

    final nowStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    for (final s in schedules) {
      if (s.active && s.time == nowStr) {
        await esp32.feedNow();
      }
    }
  }
}
