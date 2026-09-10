// lib/core/env.dart
class Env {
  static const esp32ApSsid = String.fromEnvironment('ESP32_AP_SSID', defaultValue: 'CRX-Pulse-ESP32');
  static const esp32ApPassword = String.fromEnvironment('ESP32_AP_PASSWORD', defaultValue: '');
}