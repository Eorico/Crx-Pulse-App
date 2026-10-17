import 'package:flutter/material.dart';

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
        ClipOval(
          child: Image.asset('assets/images/mascot/idle-anim.gif', width: 42, height: 42, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        // Expanded + single-line ellipsis so the title/subtitle can never
        // push past the header's fixed height (no "BOTTOM OVERFLOWED").
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, height: 1.05, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.4)),
              if (subtitle != null)
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12, height: 1.15, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}
