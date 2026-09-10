import 'package:flutter/material.dart';
import '../services/local_esp32_service.dart';

/// Shows the actual provided ESP32 chip artwork - green-glow version
/// when connected, red-glow "not connected" version otherwise. Used
/// identically on both Home and Device Setup, so a fix here covers
/// both automatically.
class ConnectionCpuIndicator extends StatelessWidget {
  final Esp32ConnectionState state;
  final double size;
  const ConnectionCpuIndicator({super.key, required this.state, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final connected = state == Esp32ConnectionState.connected;
    final asset = connected ? 'assets/images/status/cpu_connected.png' : 'assets/images/status/cpu_not_connected.png';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Image.asset(asset, key: ValueKey(connected), width: size, height: size),
    );
  }
}
