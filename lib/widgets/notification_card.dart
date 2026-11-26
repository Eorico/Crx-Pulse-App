import 'package:flutter/material.dart';

import '../core/notification_format.dart';
import '../core/theme.dart';

/// Everything the alert toast and the Notifications list need to draw the
/// same card. A null [notificationId] marks a connection message, which has
/// no stored row to open or mark read.
class NotificationToastData {
  final String title;
  final String message;
  final DateTime timestamp;
  final IconData icon;
  final Color accent;
  final int? notificationId;

  const NotificationToastData({
    required this.title,
    required this.message,
    required this.timestamp,
    required this.icon,
    required this.accent,
    this.notificationId,
  });
}

/// Facebook-shaped notification row: icon avatar, bold source line, message,
/// and the full date/time beneath. One layout shared by the toast and the
/// list so the two never drift apart.
class NotificationCard extends StatelessWidget {
  final NotificationToastData data;
  final VoidCallback? onTap;
  final bool compact;

  const NotificationCard({
    super.key,
    required this.data,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(compact ? 16 : 14),
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: data.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(data.icon, color: data.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    data.message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    formatNotificationTime(data.timestamp),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (data.notificationId != null) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
