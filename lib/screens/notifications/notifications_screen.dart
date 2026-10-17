import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../services/local_notification_provider.dart';
import '../../widgets/minimal_gif_header.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/motion.dart';
import '../../widgets/sticky_header_delegate.dart';

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

    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: FadeIn(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => provider.fetchNotifications(),
            child: CustomScrollView(
              slivers: [
                // PINNED - stays visible the whole time you scroll
                // through the notification list beneath it.
                SliverPersistentHeader(
                  pinned: true,
                  delegate: StickyHeaderDelegate(
                    height: 76,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Expanded, because MinimalGifHeader's own Row
                          // contains an Expanded: as a plain Row child
                          // it would be laid out with an unbounded
                          // width and throw.
                          const Expanded(child: MinimalGifHeader(title: 'Notifications')),
                          // Reveals and hides itself rather than
                          // popping the header layout.
                          AnimatedSize(
                            duration: AppMotion.normal,
                            curve: AppMotion.smooth,
                            child: provider.unreadCount > 0
                                ? TextButton(
                                    onPressed: () => provider.markAllRead(),
                                    child: const Text('Mark all read',
                                        style: TextStyle(color: Colors.white)),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (provider.notifications.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: FadeSlideIn(
                        beginScale: 0.92,
                        from: Offset.zero,
                        child: Column(children: [
                          Icon(LucideIcons.bellOff, color: AppColors.textMuted, size: 40),
                          SizedBox(height: 12),
                          Text('No alerts yet', style: TextStyle(color: AppColors.textSecondary)),
                          SizedBox(height: 4),
                          Text("You'll see something here if a reading goes out of range",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ]),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    sliver: SliverList.builder(
                      itemCount: provider.notifications.length,
                      itemBuilder: (context, i) {
                        final n = provider.notifications[i];
                        return Dismissible(
                          key: ValueKey(n.id),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => provider.deleteNotification(n.id),
                          background: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            alignment: Alignment.centerRight,
                            decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(14)),
                            child: const Icon(LucideIcons.trash2, color: Colors.white, size: 20),
                          ),
                          // Rows slide in from the right, one after the
                          // next, so the list assembles itself instead
                          // of appearing all at once.
                          child: FadeSlideIn(
                            delay: AppMotion.delayFor(i, max: 8),
                            from: const Offset(0.10, 0),
                            child: AnimatedContainer(
                              duration: AppMotion.normal,
                              curve: AppMotion.smooth,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: n.read
                                    ? Colors.white
                                    : AppColors.warning.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: AppShadows.card,
                              ),
                              child: Row(
                                children: [
                                  // Unread alerts pulse; read ones sit still.
                                  PulseHalo(
                                    color: AppColors.warning,
                                    active: !n.read,
                                    maxRadius: 10,
                                    child: const Icon(LucideIcons.alertTriangle,
                                        color: AppColors.warning, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(n.message,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600, fontSize: 13)),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${n.createdAt.hour.toString().padLeft(2, '0')}:${n.createdAt.minute.toString().padLeft(2, '0')}',
                                          style: const TextStyle(
                                              color: AppColors.textMuted, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
