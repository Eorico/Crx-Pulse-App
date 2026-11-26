import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/notification_type.dart';
import '../../core/theme.dart';
import '../../services/local_notification_provider.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/motion.dart';

/// Full view of a single alert. The list row only has room for a snippet,
/// so this page shows every field the local notification holds plus the
/// sensor artwork that identifies what the alert was about.
class NotificationDetailScreen extends StatelessWidget {
  final AppNotification notification;

  const NotificationDetailScreen({
    super.key,
    required this.notification,
  });

  @override
  Widget build(BuildContext context) {
    final type = notification.type;
    final severityColor = _severityColor(notification.severity);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: FadeIn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(type: type, severity: notification.severity),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MessageCard(
                        message: notification.message,
                        color: severityColor,
                      ),
                      const SizedBox(height: 16),
                      _DetailsCard(notification: notification, type: type),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(LucideIcons.arrowLeft, size: 16),
                        label: const Text('Back to notifications'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.button),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _severityColor(String severity) {
    return switch (severity.toLowerCase()) {
      'warning' => AppColors.warning,
      'error' || 'critical' || 'danger' => AppColors.danger,
      _ => AppColors.primary,
    };
  }
}

class _Header extends StatelessWidget {
  final NotificationType type;
  final String severity;

  const _Header({required this.type, required this.severity});

  @override
  Widget build(BuildContext context) {
    final severityLabel = severity.isEmpty
        ? 'Alert'
        : '${severity[0].toUpperCase()}${severity.substring(1)} alert';

    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(40),
              bottomRight: Radius.circular(40),
            ),
          ),
          child: Column(
            children: FadeSlideIn.stagger([
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  type.imageAsset,
                  width: 84,
                  height: 84,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                type.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                severityLabel,
                style: const TextStyle(
                  color: Color(0xFFC8D8C8),
                  fontSize: 14,
                ),
              ),
            ]),
          ),
        ),
        Positioned(
          left: 20,
          top: 12,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(LucideIcons.chevronLeft,
                  color: Colors.white, size: 22),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  final String message;
  final Color color;

  const _MessageCard({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                'Alert details',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final AppNotification notification;
  final NotificationType type;

  const _DetailsCard({required this.notification, required this.type});

  @override
  Widget build(BuildContext context) {
    final created = notification.createdAt;
    final date = '${created.year.toString().padLeft(4, '0')}-'
        '${created.month.toString().padLeft(2, '0')}-'
        '${created.day.toString().padLeft(2, '0')}';
    final time = '${created.hour.toString().padLeft(2, '0')}:'
        '${created.minute.toString().padLeft(2, '0')}:'
        '${created.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          _DetailRow(label: 'Notification ID', value: '#${notification.id}'),
          _DetailRow(label: 'Sensor', value: type.label),
          _DetailRow(
            label: 'Severity',
            value: notification.severity.isEmpty
                ? '—'
                : notification.severity[0].toUpperCase() +
                    notification.severity.substring(1),
          ),
          _DetailRow(label: 'Date', value: date),
          _DetailRow(label: 'Time', value: time),
          _DetailRow(
            label: 'Status',
            value: notification.read ? 'Read' : 'Unread',
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
