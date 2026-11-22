import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/feeding_schedule.dart';
import '../core/firmware_spec.dart';
import '../core/theme.dart';
import '../services/local_feeding_provider.dart';
import 'feeding_calendar.dart';
import 'motion.dart';

/// Opens the editor for one or more device-local dates.
///
/// The returned map is keyed by section date — `everyDayKey` stays a legacy
/// section until its "Change date" action moves it. Nothing is written to
/// Supabase here; the caller applies the returned drafts.
Future<Map<String, List<FeedingDraft>>?> showFeedingDateEditor(
  BuildContext context, {
  required List<String> dates,
  required Map<String, List<FeedingDraft>> initialByDate,
  required List<FeedingSchedule> existing,
  Set<String> excludedIds = const {},
}) {
  return showDialog<Map<String, List<FeedingDraft>>>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => _FeedingDateEditor(
      dates: dates,
      initialByDate: initialByDate,
      existing: existing,
      excludedIds: excludedIds,
    ),
  );
}

class _FeedingDateEditor extends StatefulWidget {
  const _FeedingDateEditor({
    required this.dates,
    required this.initialByDate,
    required this.existing,
    required this.excludedIds,
  });

  final List<String> dates;
  final Map<String, List<FeedingDraft>> initialByDate;
  final List<FeedingSchedule> existing;
  final Set<String> excludedIds;

  @override
  State<_FeedingDateEditor> createState() => _FeedingDateEditorState();
}

class _FeedingDateEditorState extends State<_FeedingDateEditor> {
  static const String _defaultTime = '08:00';
  static const int _defaultGrams = 10;

  late Map<String, List<FeedingDraft>> _byDate;

  @override
  void initState() {
    super.initState();
    _byDate = <String, List<FeedingDraft>>{
      for (final date in widget.dates)
        date: _rowsFor(date, widget.initialByDate[date]),
    };
  }

  List<FeedingDraft> _rowsFor(String date, List<FeedingDraft>? initial) {
    if (initial == null || initial.isEmpty) return [_newDraft(date)];
    return List<FeedingDraft>.from(initial);
  }

  FeedingDraft _newDraft(String date) => FeedingDraft(
        feedDate: date == everyDayKey ? null : date,
        time: _defaultTime,
        grams: _defaultGrams,
        rotatorPwm: FirmwareSpec.rotatorDefaultPwm,
      );

  void _addFeed(String date) {
    setState(() => _byDate[date] = [..._byDate[date]!, _newDraft(date)]);
  }

  void _removeFeed(String date, int index) {
    setState(() {
      final rows = List<FeedingDraft>.from(_byDate[date]!);
      rows.removeAt(index);
      _byDate[date] = rows;
    });
  }

  void _updateFeed(String date, int index, FeedingDraft draft) {
    setState(() {
      final rows = List<FeedingDraft>.from(_byDate[date]!);
      rows[index] = draft;
      _byDate[date] = rows;
    });
  }

  Future<void> _changeDate(String oldDate) async {
    final chosen = await showFeedingCalendar(
      context,
      selected: oldDate == everyDayKey ? const [] : [oldDate],
      initialMode: FeedingCalendarMode.single,
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    final newDate = chosen.first;
    if (newDate == oldDate) return;
    if (_byDate.containsKey(newDate)) {
      _toast('There is already a section for $newDate');
      return;
    }

    // A dated section writes its date onto every row. Leaving feedDate null
    // would keep the device firing the moved rows every day.
    final moved = [
      for (final draft in _byDate[oldDate]!)
        FeedingDraft(
          id: draft.id,
          feedDate: newDate,
          time: draft.time,
          grams: draft.grams,
          rotatorPwm: draft.rotatorPwm,
        ),
    ];
    setState(() {
      final keys = _byDate.keys.toList();
      keys[keys.indexOf(oldDate)] = newDate;
      _byDate = {
        for (final key in keys)
          key: key == newDate ? moved : _byDate[key]!,
      };
    });
  }

  void _save() {
    final drafts = _byDate.values.expand((rows) => rows).toList();
    final conflict = firstConflict(
      drafts,
      widget.existing
          .where((row) => !widget.excludedIds.contains(row.id))
          .toList(),
    );
    if (conflict != null) {
      _toast('Already a feed at $conflict', isConflict: true);
      return;
    }
    Navigator.of(context).pop(Map<String, List<FeedingDraft>>.from(_byDate));
  }

  void _toast(String message, {bool isConflict = false}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            key: isConflict ? const Key('feeding-date-editor-conflict') : null,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                children: [
                  for (final entry in _byDate.entries)
                    _DateSection(
                      key: Key('feeding-date-section-${entry.key}'),
                      date: entry.key,
                      drafts: entry.value,
                      onAdd: () => _addFeed(entry.key),
                      onChangeDate: () => _changeDate(entry.key),
                      onChanged: (index, draft) =>
                          _updateFeed(entry.key, index, draft),
                      onRemove: (index) => _removeFeed(entry.key, index),
                    ),
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 20, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppShadows.claySoft,
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('feeding-date-editor-cancel'),
            icon: const Icon(Icons.close, color: AppColors.textPrimary),
            tooltip: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Edit feeds',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${_byDate.length} date${_byDate.length == 1 ? '' : 's'} · '
                  '${FirmwareSpec.deviceTimezoneLabel}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
        boxShadow: AppShadows.claySoft,
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          key: const Key('feeding-date-editor-save'),
          onPressed: _save,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Save'),
        ),
      ),
    );
  }
}

/// One date's feeds. Rows stay mounted while collapsed so an in-progress
/// edit is not lost when the section is folded away.
class _DateSection extends StatefulWidget {
  const _DateSection({
    super.key,
    required this.date,
    required this.drafts,
    required this.onAdd,
    required this.onChangeDate,
    required this.onChanged,
    required this.onRemove,
  });

  final String date;
  final List<FeedingDraft> drafts;
  final VoidCallback onAdd;
  final VoidCallback onChangeDate;
  final void Function(int index, FeedingDraft draft) onChanged;
  final void Function(int index) onRemove;

  @override
  State<_DateSection> createState() => _DateSectionState();
}

class _DateSectionState extends State<_DateSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 0, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.date == everyDayKey
                            ? 'Every day (legacy)'
                            : widget.date,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${widget.drafts.length} feed'
                        '${widget.drafts.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton(
                key: Key('feeding-date-change-${widget.date}'),
                onPressed: widget.onChangeDate,
                child: const Text('Change date'),
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
          AnimatedSize(
            duration: AppMotion.normal,
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < widget.drafts.length; i++)
                        _FeedRow(
                          key: Key('feeding-feed-row-${widget.date}-$i'),
                          date: widget.date,
                          index: i,
                          draft: widget.drafts[i],
                          onChanged: (draft) => widget.onChanged(i, draft),
                          onRemove: () => widget.onRemove(i),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: OutlinedButton.icon(
                          key: Key('feeding-add-feed-${widget.date}'),
                          onPressed: widget.onAdd,
                          icon: const Icon(LucideIcons.plus, size: 18),
                          label: const Text('Add another feed'),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// A single feed's time, dose, rotator speed and remove action.
class _FeedRow extends StatelessWidget {
  const _FeedRow({
    super.key,
    required this.date,
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });

  final String date;
  final int index;
  final FeedingDraft draft;
  final ValueChanged<FeedingDraft> onChanged;
  final VoidCallback onRemove;

  Future<void> _pickTime(BuildContext context) async {
    final parts = draft.time.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 8,
        minute: int.tryParse(parts.last) ?? 0,
      ),
      initialEntryMode: TimePickerEntryMode.dial,
      helpText: 'FEEDING TIME (${FirmwareSpec.deviceTimezoneLabel.toUpperCase()})',
      builder: AppTheme.timePickerBuilder,
    );
    if (picked == null) return;
    final time = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    onChanged(FeedingDraft(
      id: draft.id,
      feedDate: draft.feedDate,
      time: time,
      grams: draft.grams,
      rotatorPwm: draft.rotatorPwm,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: PressableScale(
                  key: Key('feeding-feed-time-$date-$index'),
                  onTap: () => _pickTime(context),
                  pressedScale: 0.985,
                  child: Row(
                    children: [
                      const Icon(LucideIcons.clock, size: 18,
                          color: AppColors.primary),
                      const SizedBox(width: 10),
                      Text(
                        draft.time,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          FirmwareSpec.deviceTimezoneLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 18, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: Key('feeding-remove-feed-$date-$index'),
                tooltip: 'Remove feed',
                icon: const Icon(LucideIcons.trash2,
                    size: 18, color: AppColors.danger),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _LabelledDropdown<int>(
                  dropdownKey: Key('feeding-feed-grams-$date-$index'),
                  label: 'Dose',
                  value: draft.grams,
                  items: [
                    for (final grams in FirmwareSpec.feedGramOptions)
                      DropdownMenuItem<int>(
                        value: grams,
                        child: Text('$grams grams'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    onChanged(FeedingDraft(
                      id: draft.id,
                      feedDate: draft.feedDate,
                      time: draft.time,
                      grams: value,
                      rotatorPwm: draft.rotatorPwm,
                    ));
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LabelledDropdown<int>(
                  dropdownKey: Key('feeding-feed-rotator-$date-$index'),
                  label: 'Rotator speed',
                  value: draft.rotatorPwm,
                  items: [
                    for (final speed in FirmwareSpec.rotatorSpeeds)
                      DropdownMenuItem<int>(
                        value: speed.pwm,
                        child: Text(speed.pwm == 0
                            ? '${speed.label} — no rotation'
                            : '${speed.label}  ·  PWM ${speed.pwm}'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    onChanged(FeedingDraft(
                      id: draft.id,
                      feedDate: draft.feedDate,
                      time: draft.time,
                      grams: draft.grams,
                      rotatorPwm: value,
                    ));
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The same clay dropdown well used on the feeding screen.
class _LabelledDropdown<T> extends StatelessWidget {
  const _LabelledDropdown({
    required this.dropdownKey,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final Key dropdownKey;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              key: dropdownKey,
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(16),
              icon: const Icon(LucideIcons.chevronDown,
                  size: 18, color: AppColors.textSecondary),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
