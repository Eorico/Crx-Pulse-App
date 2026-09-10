import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Small, minimal header - the idle mascot animation on the left,
/// screen title on the right. Shared across Management, Device
/// Setup, and Notifications so the treatment stays consistent
/// everywhere it's used.
class MinimalGifHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const MinimalGifHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: Image.asset('assets/images/mascot/idle-anim.gif', width: 70, height: 70, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.5)),
            if (subtitle != null)
              Text(subtitle!, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}
