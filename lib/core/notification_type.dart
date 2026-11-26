import 'sensor_icons.dart';

/// Which sensor produced an alert.
///
/// Alerts are stored with only a free-text message, so the type is
/// recovered from that message instead of a dedicated database column.
/// Every phrase comes from LocalNotificationProvider.checkThresholds,
/// which keeps the matching stable; anything else is treated as a
/// general system alert.
enum NotificationType {
  ph,
  ammonia,
  turbidity,
  waterTemp,
  housingTemp,
  general;

  static NotificationType fromMessage(String message) {
    final text = message.toLowerCase();
    if (text.startsWith('ph ')) return ph;
    if (text.contains('ammonia')) return ammonia;
    if (text.contains('turbidity')) return turbidity;
    if (text.contains('housing temp')) return housingTemp;
    if (text.contains('water temp')) return waterTemp;
    return general;
  }

  /// Short sensor name shown above the alert title.
  String get label => switch (this) {
        ph => 'pH Sensor',
        ammonia => 'Ammonia Sensor',
        turbidity => 'Turbidity Sensor',
        waterTemp => 'Water Temperature',
        housingTemp => 'Housing Temperature',
        general => 'System',
      };

  /// Artwork shown on the alert detail screen. Each sensor already has
  /// its own asset in `assets/images/sensors`, so no new images are
  /// needed — an ammonia alert simply gets the ammonia artwork.
  String get imageAsset => switch (this) {
        ph => SensorIcons.ph,
        ammonia => SensorIcons.ammonia,
        turbidity => SensorIcons.turbidity,
        waterTemp => SensorIcons.waterTemp,
        housingTemp => SensorIcons.housingTemp,
        general => SensorIcons.bell,
      };
}
