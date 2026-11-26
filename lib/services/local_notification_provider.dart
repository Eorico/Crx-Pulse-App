import 'package:flutter/foundation.dart';
import '../core/firmware_spec.dart';
import '../core/notification_type.dart';
import 'local_db.dart';
import 'local_esp32_service.dart';

class AppNotification {
  final int id;
  final String message;
  final String severity;
  final DateTime createdAt;
  final bool read;

  const AppNotification({required this.id, required this.message, required this.severity, required this.createdAt, required this.read});

  /// Sensor this alert belongs to, used to pick the detail-screen image.
  NotificationType get type => NotificationType.fromMessage(message);

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
    id: m['id'] as int,
    message: m['message'] as String,
    severity: m['severity'] as String,
    createdAt: DateTime.parse(m['created_at'] as String),
    read: (m['read'] as int) == 1,
  );
}

/// Generates real alerts from live sensor thresholds (matching the
/// same safe-range checks already used on the sensor cards) and
/// stores them in SQLite - restores notification history without a
/// backend. Only logs a NEW notification on the transition into an
/// unsafe state, not on every single poll while it stays unsafe, to
/// avoid spamming the same alert every 3 seconds.
class LocalNotificationProvider extends ChangeNotifier {
  List<AppNotification> notifications = [];
  final Set<String> _currentlyUnsafe = {};

  int get unreadCount => notifications.where((n) => !n.read).length;

  Future<void> fetchNotifications() async {
    final db = await LocalDb.instance.database;
    final rows = await db.query('notifications', orderBy: 'created_at DESC', limit: 100);
    notifications = rows.map(AppNotification.fromMap).toList();
    notifyListeners();
  }

  Future<void> markAllRead() async {
    final db = await LocalDb.instance.database;
    await db.update('notifications', {'read': 1});
    await fetchNotifications();
  }

  /// Marks one alert read. Used when a toast is tapped, so opening the
  /// notification clears only the row the person actually looked at.
  Future<void> markAsRead(int id) async {
    final db = await LocalDb.instance.database;
    await db.update(
      'notifications',
      {'read': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    await fetchNotifications();
  }

  /// Removes a single notification by ID - used by the swipe-to-
  /// delete gesture. Updates the in-memory list immediately (rather
  /// than waiting on a full fetchNotifications() round-trip) so the
  /// Dismissible's own removal animation isn't fighting a list that
  /// hasn't caught up yet.
  Future<void> deleteNotification(int id) async {
    final db = await LocalDb.instance.database;
    await db.delete('notifications', where: 'id = ?', whereArgs: [id]);
    notifications = notifications.where((n) => n.id != id).toList();
    notifyListeners();
  }

  Future<void> _log(String message, String severity) async {
    final db = await LocalDb.instance.database;
    await db.insert('notifications', {
      'message': message, 'severity': severity,
      'created_at': DateTime.now().toIso8601String(), 'read': 0,
    });
    await fetchNotifications();
  }

  /// Called on every LocalEsp32Service update - checks each reading
  /// against its safe range and logs a notification only on the
  /// transition from safe -> unsafe (tracked via _currentlyUnsafe),
  /// clearing the flag again once it's back in range so a future
  /// breach logs a fresh alert instead of staying silent forever.
  ///
  /// Every range comes from [FirmwareSpec], so an alert fires at
  /// exactly the point the sensor cards turn red and (for turbidity and
  /// housing temperature) at exactly the point the firmware itself
  /// changes behaviour. These used to be loose literals here — 50%
  /// turbidity instead of the firmware's "Turbid" band edge, and no
  /// housing-temperature check at all even though overheating is what
  /// the cooling fan exists for.
  Future<void> checkThresholds(LocalEsp32Service esp32) async {
    await _check('ph', esp32.ph, FirmwareSpec.phIsSafe,
        'pH is out of the safe range');
    await _check('ammonia', esp32.ammonia, FirmwareSpec.ammoniaIsSafe,
        'Ammonia level is too high');
    await _check('turbidity', esp32.turbidity, FirmwareSpec.turbidityIsSafe,
        'Water turbidity is too high');
    await _check('water_temp', esp32.waterTempC, FirmwareSpec.waterTempIsSafe,
        'Water temperature is out of range');
    await _check('housing_temp', esp32.ambientTempC, FirmwareSpec.housingTempIsSafe,
        'Housing temperature is high — cooling fan at full speed');
  }

  Future<void> _check(String key, double? value, bool Function(double) isSafe, String message) async {
    if (value == null) return;
    final safe = isSafe(value);
    if (!safe && !_currentlyUnsafe.contains(key)) {
      _currentlyUnsafe.add(key);
      await _log(message, 'warning');
    } else if (safe && _currentlyUnsafe.contains(key)) {
      _currentlyUnsafe.remove(key);
    }
  }
}
