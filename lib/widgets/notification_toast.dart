import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'notification_card.dart';

/// The alert toast, pinned below the status bar instead of the bottom nav.
///
/// A floating SnackBar honours `margin`; the bottom-anchored fixed one does
/// not, which is why the theme's floating behavior is repeated explicitly
/// here.
SnackBar buildTopNotificationSnackBar({
  required BuildContext context,
  required NotificationToastData data,
  VoidCallback? onTap,
}) {
  final top = MediaQuery.of(context).padding.top + 12;
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.fromLTRB(16, top, 16, 0),
    padding: EdgeInsets.zero,
    backgroundColor: AppColors.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    content: NotificationCard(data: data, onTap: onTap, compact: true),
    duration: const Duration(seconds: 4),
  );
}
