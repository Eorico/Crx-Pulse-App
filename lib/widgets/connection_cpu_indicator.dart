import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/sensor_icons.dart';
import '../services/local_esp32_service.dart';
import 'motion.dart';

/// Shows the ESP32 chip artwork — green-glow version when connected,
/// red-glow "not connected" version otherwise. Used identically on both
/// Home and Device Setup, so a fix here covers both.
///
/// A connected chip carries a slow green halo, which is the app's one
/// ambient "data is arriving" signal; a disconnected one sits still
/// under a red halo. The two images cross-fade rather than cutting.
class ConnectionCpuIndicator extends StatelessWidget {
  final Esp32ConnectionState state;
  final double size;
  const ConnectionCpuIndicator({super.key, required this.state, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final connected = state == Esp32ConnectionState.connected;
    final asset = connected ? StatusIcons.connected : StatusIcons.notConnected;

    return PulseHalo(
      color: connected ? AppColors.success : AppColors.danger,
      active: connected,
      maxRadius: size * 0.35,
      child: SwapIn(
        swapKey: connected,
        child: Image.asset(asset, width: size, height: size),
      ),
    );
  }
}
