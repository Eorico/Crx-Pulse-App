import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../services/local_notification_provider.dart';
import '../../widgets/minimal_gif_header.dart';
import '../../widgets/fade_in.dart';

class LocalNotificationsScreen extends StatefulWidget {
  const LocalNotificationsScreen({super.key});

  @override
  State<LocalNotificationsScreen> createState() => _LocalNotificationsScreenState();
}

class _LocalNotificationsScreenState extends State<LocalNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocalNotificationProvider>().fetchNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocalNotificationProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeIn(
          child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const MinimalGifHeader(title: 'Notifications'),
                  if (provider.unreadCount > 0)
                    TextButton(onPressed: () => provider.markAllRead(), child: const Text('Mark all read')),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => provider.fetchNotifications(),
                child: provider.notifications.isEmpty
                    ? ListView(children: [
                        SizedBox(height: 100),
                        Icon(LucideIcons.bellOff, color: AppColors.textMuted, size: 40),
                        SizedBox(height: 12),
                        Center(child: Text('No alerts yet', style: TextStyle(color: AppColors.textSecondary))),
                        SizedBox(height: 4),
                        Center(child: Text("You'll see something here if a reading goes out of range", style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: provider.notifications.length,
                        itemBuilder: (context, i) {
                          final n = provider.notifications[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: n.read ? Colors.white : AppColors.warning.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: AppShadows.card,
                            ),
                            child: Row(
                              children: [
                                Icon(LucideIcons.alertTriangle, color: AppColors.warning, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(n.message, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${n.createdAt.hour.toString().padLeft(2, '0')}:${n.createdAt.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
