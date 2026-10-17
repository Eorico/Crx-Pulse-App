/// Custom sensor icons, replacing the generic Lucide icons for these
/// specific readings.
class SensorIcons {
  static const ph = 'assets/images/sensors/ph.gif';
  static const ammonia = 'assets/images/sensors/ammonia.gif';
  static const turbidity = 'assets/images/sensors/turbidity.gif';
  static const waterTemp = 'assets/images/sensors/water-temp.gif';
  static const housingTemp = 'assets/images/sensors/housing-temp.gif';
  static const fan = 'assets/images/sensors/fan.png';

  /// Animated summary/alert icons used on the dashboard.
  static const stats = 'assets/images/sensors/stats.gif';
  static const bell = 'assets/images/sensors/bell.gif';
}

/// Connection status illustrations - swapped based on whether the
/// ESP32 is actually reachable.
///
/// [connected] pointed at `connected.png`, which does not exist in
/// assets — the real file is `cpu_connected.png`. Nothing broke only
/// because ConnectionCpuIndicator had its own hard-coded copies of
/// these paths; it now uses these constants, so they have to be right.
class StatusIcons {
  static const connected = 'assets/images/status/cpu_connected.png';
  static const notConnected = 'assets/images/status/cpu_not_connected.png';
}
