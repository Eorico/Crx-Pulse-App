import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/feeding_schedule.dart';
import '../core/firmware_spec.dart';
import '../core/theme.dart';
import '../services/device_provider.dart';
import '../services/local_feeding_provider.dart';
import 'feeding_calendar.dart';
import 'feeding_date_editor.dart';
import 'motion.dart';

/// Date-grouped view of the saved schedules. Each card is one device-local
/// date; legacy rows without a date share the "Every day" card until it is
/// explicitly converted. Edits go through the same per-date editor used to
/// create feeds, so a group can change its date and every row in one write.
class FeedingOverview extends StatelessWidget {
  const FeedingOverview({super.key});

  @override
  Widget build(BuildContext context) {
    final feeding = context.watch<LocalFeedingProvider>();
    final deviceId = context.watch<DeviceProvider>().deviceId;
    final paired = deviceId != null;
    final groups = groupFeedsByDate(feeding.schedulesForDevice(deviceId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 0, 0, 8),
          child: Text(
            'Scheduled feeds',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.normal,
          curve: AppMotion.smooth,
          alignment: Alignment.topCenter,
          child: feeding.isLoading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              : groups.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No feeding dates yet — choose dates above to add some.',
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: FadeSlideIn.stagger(
                        [
                          for (final group in groups)
                            _DateGroupCard(group: group, paired: paired),
                        ],
                        from: const Offset(-0.08, 0),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _DateGroupCard extends StatefulWidget {
  const _DateGroupCard({required this.group, required this.paired});

  final FeedingDateGroup group;
  final bool paired;

  @override
  State<_DateGroupCard> createState() => _DateGroupCardState();
}

class _DateGroupCardState extends State<_DateGroupCard> {
  bool _expanded = true;

  String get _key => widget.group.date ?? everyDayKey;

  bool get _isLegacy =>
      widget.group.date == null || widget.group.date == everyDayKey;

  String get _label => _isLegacy ? 'Every day' : widget.group.date!;

  Future<void> _edit() async {
    final group = widget.group;
    final dateKey = _key;
    final result = await showFeedingDateEditor(
      context,
      dates: [dateKey],
      initialByDate: {
        dateKey: [
          for (final feed in group.feeds)
            FeedingDraft(
              id: feed.id,
              feedDate: feed.feedDate,
              time: feed.time,
              grams: feed.grams,
              rotatorPwm: feed.rotatorPwm,
            ),
        ],
      },
      // Conflict checks see only schedules saved for this device. The group
      // being edited excludes its own rows: it supplies them as drafts
      // instead.
      existing: context
          .read<LocalFeedingProvider>()
          .schedulesForDevice(context.read<DeviceProvider>().deviceId),
      excludedIds: group.feeds.map((feed) => feed.id).toSet(),
    );
    if (result == null || !mounted || result.isEmpty) return;

    // The editor may have moved the section to another date, so the map key
    // is the source of truth rather than the group we opened with.
    final entry = result.entries.first;
    final newDate = entry.key == everyDayKey ? null : entry.key;
    final deviceId = context.read<DeviceProvider>().deviceId;
    if (deviceId == null) return;
    await context.read<LocalFeedingProvider>().updateScheduleGroup(
          deviceId,
          newDate,
          group.feeds,
          entry.value,
        );
  }

  Future<void> _convertToDate() async {
    final chosen = await showFeedingCalendar(
      context,
      initialMode: FeedingCalendarMode.single,
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    final date = chosen.first;

    final provider = context.read<LocalFeedingProvider>();
    final deviceId = context.read<DeviceProvider>().deviceId;
    if (deviceId == null) return;
    final alreadyDated = groupFeedsByDate(provider.schedulesForDevice(deviceId))
        .any((group) => group.date == date);
    if (alreadyDated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('There is already a section for $date')),
      );
      return;
    }

    final group = widget.group;
    await provider.updateScheduleGroup(
      deviceId,
      date,
      group.feeds,
      [
        for (final feed in group.feeds)
          FeedingDraft(
            id: feed.id,
            feedDate: date,
            time: feed.time,
            grams: feed.grams,
            rotatorPwm: feed.rotatorPwm,
          ),
      ],
    );
  }

  void _delete() {
    final provider = context.read<LocalFeedingProvider>();
    provider.deleteSchedules(
      widget.group.feeds.map((feed) => feed.id).toSet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final dateKey = _key;

    return Container(
      key: Key('feeding-overview-group-$dateKey'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${group.feeds.length} feed'
                        '${group.feeds.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _expanded ? 'Collapse' : 'Expand',
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton(
                  key: Key('feeding-overview-edit-$dateKey'),
                  onPressed: widget.paired ? _edit : null,
                  child: const Text('Edit'),
                ),
                IconButton(
                  key: Key('feeding-overview-delete-$dateKey'),
                  tooltip: 'Delete date',
                  icon: const Icon(LucideIcons.trash2,
                      size: 18, color: AppColors.danger),
                  onPressed: widget.paired ? _delete : null,
                ),
                if (_isLegacy)
                  TextButton(
                    key: const Key('feeding-overview-convert-every-day'),
                    onPressed: widget.paired ? _convertToDate : null,
                    child: const Text('Convert to date'),
                  ),
              ],
            ),
          ),
          AnimatedSize(
            duration: AppMotion.normal,
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final feed in group.feeds)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Text(
                                  feed.time,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${feed.grams}g · rotator '
                                    '${FirmwareSpec.rotatorSpeedForPwm(feed.rotatorPwm).label}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
