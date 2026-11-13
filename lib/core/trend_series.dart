import 'dart:math' as math;

/// One point on a trend chart: a value and the moment it was recorded.
class TrendSample {
  final DateTime t;
  final double v;
  const TrendSample(this.t, this.v);
}

/// A metric's history over a window, reduced to something paintable.
///
/// The charts used to plot values by list index, which silently lies
/// about time: a gap where the device was unplugged for six hours
/// looked exactly like the five seconds between two consecutive
/// readings. Carrying the timestamps lets the trend be drawn against a
/// real time axis, and lets the axis be labelled with dates.
class TrendSeries {
  /// Time-ordered, and thinned to at most `maxBuckets` points.
  final List<TrendSample> samples;

  /// How many readings went into [samples] before thinning.
  final int rawCount;

  /// Window actually covered by the data (not the requested window).
  final DateTime? start;
  final DateTime? end;

  final double minV;
  final double maxV;

  const TrendSeries({
    required this.samples,
    required this.rawCount,
    required this.start,
    required this.end,
    required this.minV,
    required this.maxV,
  });

  static const TrendSeries empty = TrendSeries(
    samples: [], rawCount: 0, start: null, end: null, minV: 0, maxV: 0,
  );

  bool get isEmpty => samples.isEmpty;

  /// Seconds from [start] to [end]; 0 when there is nothing or one point.
  double get spanSeconds =>
      (start == null || end == null) ? 0 : end!.difference(start!).inSeconds.toDouble().abs();

  /// Averages the readings into at most [maxBuckets] equal *time*
  /// buckets.
  ///
  /// Equal time, not equal count — that is what keeps the x axis
  /// honest. Buckets with no readings are dropped rather than
  /// interpolated, so the line simply spans the gap instead of
  /// inventing points inside it.
  ///
  /// A 30-day window at the firmware's publish rate is hundreds of
  /// thousands of points; painting them all would mean many per pixel
  /// for no visible gain. Note the thinning is for *drawing* only —
  /// zone counts and distributions are computed from every raw row.
  factory TrendSeries.build(List<TrendSample> raw, {int maxBuckets = 180}) {
    if (raw.isEmpty) return empty;

    final sorted = [...raw]..sort((a, b) => a.t.compareTo(b.t));
    final first = sorted.first.t;
    final last = sorted.last.t;

    double lo = sorted.first.v, hi = sorted.first.v;
    for (final s in sorted) {
      lo = math.min(lo, s.v);
      hi = math.max(hi, s.v);
    }

    if (sorted.length <= maxBuckets) {
      return TrendSeries(
        samples: sorted, rawCount: sorted.length,
        start: first, end: last, minV: lo, maxV: hi,
      );
    }

    final spanMs = last.difference(first).inMilliseconds;
    if (spanMs <= 0) {
      // Everything landed on the same instant — one averaged point.
      final mean = sorted.map((s) => s.v).reduce((a, b) => a + b) / sorted.length;
      return TrendSeries(
        samples: [TrendSample(first, mean)], rawCount: sorted.length,
        start: first, end: last, minV: lo, maxV: hi,
      );
    }

    final sums = List<double>.filled(maxBuckets, 0);
    final hits = List<int>.filled(maxBuckets, 0);
    for (final s in sorted) {
      final offset = s.t.difference(first).inMilliseconds;
      final b = ((offset * maxBuckets) ~/ spanMs).clamp(0, maxBuckets - 1);
      sums[b] += s.v;
      hits[b]++;
    }

    final out = <TrendSample>[];
    for (int b = 0; b < maxBuckets; b++) {
      if (hits[b] == 0) continue;
      // Date the bucket at its midpoint, so a point sits where its
      // readings actually were rather than at a bucket edge.
      final ms = ((b + 0.5) * spanMs / maxBuckets).round();
      out.add(TrendSample(first.add(Duration(milliseconds: ms)), sums[b] / hits[b]));
    }

    return TrendSeries(
      samples: out, rawCount: sorted.length,
      start: first, end: last, minV: lo, maxV: hi,
    );
  }

  /// Up to [count] evenly spaced instants across the window, for the
  /// x-axis ticks. Returns fewer when the window is degenerate.
  List<DateTime> axisTicks(int count) {
    if (start == null || end == null || count < 2) return const [];
    final spanMs = end!.difference(start!).inMilliseconds;
    if (spanMs <= 0) return [start!];
    return [
      for (int i = 0; i < count; i++)
        start!.add(Duration(milliseconds: (spanMs * i / (count - 1)).round())),
    ];
  }
}

/// Date and time formatting for the charts.
///
/// Written out by hand rather than pulling in `intl`: the app needs
/// exactly these three forms, and a new dependency for them would be
/// out of proportion.
abstract final class ChartDate {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// `14:05`
  static String hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  /// `27 Oct`
  static String dayMonth(DateTime t) => '${t.day} ${_months[t.month - 1]}';

  /// `27 Oct 25`
  static String dayMonthYear(DateTime t) =>
      '${dayMonth(t)} ${_two(t.year % 100)}';

  /// The shortest label that still distinguishes ticks at this zoom —
  /// clock time within a couple of days, dates beyond that.
  static String tick(DateTime t, double spanSeconds) {
    const day = 86400.0;
    if (spanSeconds <= day * 1.5) return hm(t);
    if (spanSeconds <= day * 365) return dayMonth(t);
    return dayMonthYear(t);
  }

  /// `27 Oct 14:05` — the fuller form used for the "covered" line.
  static String stamp(DateTime t) => '${dayMonth(t)} ${hm(t)}';

  /// `21 Oct 09:12 – 27 Oct 14:05`, collapsed to one date when both
  /// ends fall on the same day.
  static String range(DateTime a, DateTime b) {
    final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
    return sameDay
        ? '${dayMonth(a)}  ${hm(a)} – ${hm(b)}'
        : '${stamp(a)} – ${stamp(b)}';
  }
}
