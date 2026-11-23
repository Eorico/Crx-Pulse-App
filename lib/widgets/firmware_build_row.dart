import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The build tag of the firmware actually flashed on the board.
///
/// The tag only exists on the device's own WiFi, so an unknown tag is a
/// normal state, not an error: the hint says where to find it instead of
/// leaving an unexplained dash in the status card.
class FirmwareBuildRow extends StatelessWidget {
  const FirmwareBuildRow({
    super.key,
    required this.tag,
  });

  final String? tag;

  @override
  Widget build(BuildContext context) {
    final known = tag != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Firmware build',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Text(known ? tag! : '—',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          if (!known) ...[
            const SizedBox(height: 4),
            const Text(
              "Connect to the device's WiFi to read the build tag",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
