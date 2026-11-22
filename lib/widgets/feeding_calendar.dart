import 'package:flutter/material.dart';

import '../core/feeding_schedule.dart';
import '../core/theme.dart';
import 'motion.dart';

/// How a tap on a day changes the selection.
enum FeedingCalendarMode { single, multiple, range }

/// Opens the calendar as a full-screen dialog.
///
/// Returns the chosen device dates as sorted `YYYY-MM-DD` keys, or null when
/// the user cancels. Dates are plain calendar days: no phone-local timezone
/// conversion happens anywhere in the picker.
Future<List<String>?> showFeedingCalendar(
  BuildContext context, {
  DateTime? now,
  List<String> selected = const [],
  FeedingCalendarMode initialMode = FeedingCalendarMode.single,
}) {
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => _FeedingCalendar(
      now: now,
      selected: selected,
      initialMode: initialMode,
    ),
  );
}

class _FeedingCalendar extends StatefulWidget {
  const _FeedingCalendar({
    required this.now,
    required this.selected,
    required this.initialMode,
  });

  final DateTime? now;
  final List<String> selected;
  final FeedingCalendarMode initialMode;

  @override
  State<_FeedingCalendar> createState() => _FeedingCalendarState();
}

class _FeedingCalendarState extends State<_FeedingCalendar> {
  static const _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late final String _today;
  late final int _todayPage;
  late final PageController _pages;
  late FeedingCalendarMode _mode;
  late List<String> _selected;
  late int _page;
  String? _rangeStart;

  @override
  void initState() {
    super.initState();
    _today = deviceTodayDate(now: widget.now);
    final firstDay = _parseDay(_today);
    _todayPage = _pageOf(firstDay.year, firstDay.month);
    _page = _todayPage;
    _pages = PageController(initialPage: _todayPage);
    _mode = widget.initialMode;
    _selected = widget.selected.where((date) => !_isPast(date)).toSet().toList()
      ..sort();
    _rangeStart = _mode == FeedingCalendarMode.range && _selected.isNotEmpty
        ? _selected.first
        : null;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool _isPast(String date) => date.compareTo(_today) < 0;

  static DateTime _parseDay(String date) {
    final parts = date.split('-');
    return DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static String _formatDay(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static int _pageOf(int year, int month) => (year - 2000) * 12 + month - 1;

  static int _yearOf(int page) => 2000 + (page / 12).floor();

  static int _monthOf(int page) => page - (_yearOf(page) - 2000) * 12 + 1;

  List<String> _daysBetween(String first, String second) {
    final a = _parseDay(first);
    final b = _parseDay(second);
    final from = a.isBefore(b) ? a : b;
    final to = a.isBefore(b) ? b : a;
    final days = <String>[];
    for (
      var day = from;
      !day.isAfter(to);
      day = day.add(const Duration(days: 1))
    ) {
      days.add(_formatDay(day));
    }
    return days;
  }

  void _selectDay(String date) {
    if (_isPast(date)) return;
    setState(() {
      switch (_mode) {
        case FeedingCalendarMode.single:
          _selected = [date];
        case FeedingCalendarMode.multiple:
          _selected = _selected.contains(date)
              ? _selected.where((d) => d != date).toList()
              : [..._selected, date]..sort();
        case FeedingCalendarMode.range:
          final start = _rangeStart;
          if (start == null) {
            _rangeStart = date;
            _selected = [date];
          } else {
            _selected = _daysBetween(start, date);
            _rangeStart = null;
          }
      }
    });
  }

  void _changeMode(FeedingCalendarMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _rangeStart = mode == FeedingCalendarMode.range && _selected.isNotEmpty
          ? _selected.first
          : null;
      if (mode == FeedingCalendarMode.single && _selected.length > 1) {
        _selected = [_selected.first];
      }
    });
  }

  void _confirm(BuildContext context) {
    final dates = _selected.toList()..sort();
    Navigator.of(context).pop(dates);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            _buildQuickPicks(),
            _buildModeSelector(),
            _buildMonthBar(),
            _buildWeekdayRow(),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, page) => _buildMonth(page),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 20, 0),
      child: Row(
        children: [
          IconButton(
            key: const Key('feeding-calendar-cancel'),
            icon: const Icon(Icons.close, color: AppColors.textPrimary),
            tooltip: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select dates',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: const Text(
                    'DEVICE TIME · UTC+8',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPicks() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Wrap(
        spacing: 8,
        children: [
          _quickChip(
            key: const Key('feeding-quick-today'),
            label: 'Today',
            days: 1,
          ),
          _quickChip(
            key: const Key('feeding-quick-tomorrow'),
            label: 'Tomorrow',
            days: 2,
          ),
          _quickChip(
            key: const Key('feeding-quick-next-7'),
            label: 'Next 7 days',
            days: 7,
          ),
        ],
      ),
    );
  }

  Widget _quickChip({
    required Key key,
    required String label,
    required int days,
  }) {
    return ActionChip(
      key: key,
      label: Text(label),
      onPressed: () => _applyQuickPick(days),
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      labelStyle: const TextStyle(
        color: AppColors.primaryDark,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );
  }

  void _applyQuickPick(int days) {
    final base = _parseDay(_today);
    final selectable = <String>[
      for (var offset = 0; offset < days; offset++)
        _formatDay(base.add(Duration(days: offset))),
    ].where((date) => !_isPast(date)).toList();
    if (selectable.isEmpty) return;

    setState(() {
      if (days == 7) {
        _mode = FeedingCalendarMode.range;
        _selected = selectable;
      } else {
        _mode = FeedingCalendarMode.single;
        _selected = [selectable.last];
      }
      _rangeStart = null;
    });

    final first = _parseDay(selectable.first);
    final targetPage = _pageOf(first.year, first.month);
    if (targetPage != _page) {
      _pages.animateToPage(
        targetPage,
        duration: AppMotion.normal,
        curve: AppMotion.enter,
      );
    }
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: SegmentedButton<FeedingCalendarMode>(
        showSelectedIcon: false,
        segments: [
          for (final mode in FeedingCalendarMode.values)
            ButtonSegment<FeedingCalendarMode>(
              value: mode,
              label: KeyedSubtree(
                key: Key('feeding-mode-${mode.name}'),
                child: Text(_modeLabel(mode)),
              ),
            ),
        ],
        selected: {_mode},
        onSelectionChanged: (values) {
          if (values.isNotEmpty) _changeMode(values.first);
        },
      ),
    );
  }

  static String _modeLabel(FeedingCalendarMode mode) => switch (mode) {
        FeedingCalendarMode.single => 'Single',
        FeedingCalendarMode.multiple => 'Multiple',
        FeedingCalendarMode.range => 'Range',
      };

  Widget _buildMonthBar() {
    final year = _yearOf(_page);
    final month = _monthOf(_page);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          IconButton(
            key: const Key('feeding-calendar-prev-month'),
            icon: const Icon(Icons.chevron_left, color: AppColors.textPrimary),
            tooltip: 'Previous month',
            onPressed: _page <= _todayPage
                ? null
                : () => _pages.previousPage(
                      duration: AppMotion.normal,
                      curve: AppMotion.enter,
                    ),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${_monthNames[month - 1]} $year',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('feeding-calendar-next-month'),
            icon: const Icon(Icons.chevron_right, color: AppColors.textPrimary),
            tooltip: 'Next month',
            onPressed: () => _pages.nextPage(
              duration: AppMotion.normal,
              curve: AppMotion.enter,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Row(
        children: [
          for (final label in _weekdays)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonth(int page) {
    final year = _yearOf(page);
    final month = _monthOf(page);
    final leadingBlanks = DateTime.utc(year, month, 1).weekday - 1;
    final daysInMonth = DateTime.utc(year, month + 1, 0).day;

    return LayoutBuilder(
      builder: (context, constraints) {
        const verticalPadding = 12.0;
        const rowGap = 4.0;
        final weekCount = (leadingBlanks + daysInMonth + 6) ~/ 7;
        final cellHeight = ((constraints.maxHeight -
                    verticalPadding -
                    rowGap * (weekCount - 1)) /
                weekCount)
            .clamp(32.0, 46.0)
            .toDouble();

        final cells = <Widget>[
          for (var i = 0; i < leadingBlanks; i++) SizedBox(height: cellHeight),
          for (var day = 1; day <= daysInMonth; day++)
            _buildDay(
              _formatDay(DateTime.utc(year, month, day)),
              day,
              cellHeight,
            ),
        ];
        while (cells.length % 7 != 0) {
          cells.add(SizedBox(height: cellHeight));
        }

        final weeks = <Widget>[];
        for (var i = 0; i < cells.length; i += 7) {
          if (i > 0) weeks.add(const SizedBox(height: rowGap));
          weeks.add(
            Row(
              children: [
                for (final cell in cells.skip(i).take(7)) Expanded(child: cell),
              ],
            ),
          );
        }

        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: weeks),
          ),
        );
      },
    );
  }

  BoxDecoration _dayDecoration(String date, bool past, bool selected) {
    if (selected) {
      if (_mode == FeedingCalendarMode.single) {
        return BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(21),
          boxShadow: AppShadows.claySoft,
        );
      }
      final first = date == _selected.first;
      final last = date == _selected.last;
      final endpoint = first || last;
      return BoxDecoration(
        color: endpoint
            ? AppColors.primary
            : AppColors.primary.withValues(alpha: 0.16),
        borderRadius: endpoint
            ? first && last
                ? BorderRadius.circular(21)
                : first
                    ? const BorderRadius.horizontal(
                        left: Radius.circular(21),
                      )
                    : const BorderRadius.horizontal(
                        right: Radius.circular(21),
                      )
            : BorderRadius.zero,
        boxShadow: endpoint ? AppShadows.claySoft : null,
      );
    }
    if (past) {
      return const BoxDecoration(color: AppColors.background);
    }
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(21),
      boxShadow: AppShadows.claySoft,
    );
  }

  Widget _buildDay(String date, int day, double height) {
    final past = _isPast(date);
    final selected = _selected.contains(date);
    final today = date == _today;
    final endpoint = selected &&
        _mode != FeedingCalendarMode.single &&
        (date == _selected.first || date == _selected.last);
    final solid = selected &&
        (_mode == FeedingCalendarMode.single || endpoint);

    final Color textColor;
    if (solid) {
      textColor = Colors.white;
    } else if (selected) {
      textColor = AppColors.primaryDark;
    } else if (past) {
      textColor = AppColors.textMuted;
    } else {
      textColor = AppColors.textPrimary;
    }

    return PressableScale(
      key: Key('feeding-day-$date'),
      onTap: past ? null : () => _selectDay(date),
      child: Semantics(
        label: date,
        enabled: !past,
        selected: selected,
        child: Container(
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          decoration: _dayDecoration(date, past, selected),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      today || selected ? FontWeight.w800 : FontWeight.w600,
                  color: textColor,
                ),
              ),
              if (today)
                KeyedSubtree(
                  key: const Key('feeding-calendar-today-marker'),
                  child: Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: solid ? Colors.white : AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
        boxShadow: AppShadows.claySoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(
            key: const Key('feeding-calendar-summary'),
            child: Text(
              _selectionSummary(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            key: const Key('feeding-calendar-confirm'),
            onPressed: _selected.isEmpty ? null : () => _confirm(context),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  String _selectionSummary() {
    if (_selected.isEmpty) return 'No dates selected';
    if (_selected.length == 1) return '1 date selected · ${_selected.first}';
    if (_mode == FeedingCalendarMode.range) {
      return '${_selected.length} days · ${_selected.first} – ${_selected.last}';
    }
    return '${_selected.length} dates selected';
  }
}
