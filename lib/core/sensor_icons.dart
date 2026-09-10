/// Custom sensor icons, replacing the generic Lucide icons for these
/// specific readings.
class SensorIcons {
  static const ph = 'assets/images/sensors/ph.png';
  static const ammonia = 'assets/images/sensors/ammonia.png';
  static const turbidity = 'assets/images/sensors/turbidity.png';
  static const waterTemp = 'assets/images/sensors/water_temperature.png';
  static const housingTemp = 'assets/images/sensors/housing_temperature.png';
  static const fan = 'assets/images/sensors/fan.png';
}

/// Connection status illustrations - swapped based on whether the
/// ESP32 is actually reachable.
class StatusIcons {
  static const connected = 'assets/images/status/connected.png';
  static const notConnected = 'assets/images/status/cpu_not_connected.png';
}
