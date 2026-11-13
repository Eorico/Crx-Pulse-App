import 'package:flutter_test/flutter_test.dart';
import 'package:crx_pulse/core/trend_series.dart';

void main() {
  final t0 = DateTime(2026, 10, 20, 8, 0);

  group('TrendSeries.build', () {
    test('keeps every point when under the bucket limit', () {
      final raw = [
        for (int i = 0; i < 10; i++)
          TrendSample(t0.add(Duration(minutes: i)), i.toDouble()),
      ];
      final s = TrendSeries.build(raw, maxBuckets: 180);

      expect(s.samples.length, 10);
      expect(s.rawCount, 10);
      expect(s.minV, 0);
      expect(s.maxV, 9);
      expect(s.start, t0);
      expect(s.end, t0.add(const Duration(minutes: 9)));
    });

    test('thins to the bucket limit but reports the raw count', () {
      final raw = [
        for (int i = 0; i < 5000; i++)
          TrendSample(t0.add(Duration(seconds: i * 5)), (i % 100).toDouble()),
      ];
      final s = TrendSeries.build(raw, maxBuckets: 180);

      expect(s.samples.length, lessThanOrEqualTo(180));
      expect(s.rawCount, 5000);
      // Thinning must not change the window or the extremes the
      // y-axis labels are drawn from.
      expect(s.start, t0);
      expect(s.end, t0.add(const Duration(seconds: 4999 * 5)));
      expect(s.minV, 0);
      expect(s.maxV, 99);
    });

    test('a value is plotted at the time it was recorded', () {
      // A burst then a trickle: 960 readings all reading 1.0 crammed
      // into the first hour, then 24 readings of 2.0 spread over the
      // next 24 hours.
      //
      // This is what separates the two thinning strategies. Equal-
      // COUNT bucketing gives the busy hour ~97% of the buckets, so
      // the 1.0s get smeared across the whole axis and a point dated
      // noon carries a value recorded at 08:30. Equal-TIME bucketing
      // must keep every 1.0 inside the first hour.
      final raw = <TrendSample>[
        for (int i = 0; i < 960; i++)
          TrendSample(t0.add(Duration(milliseconds: i * 3750)), 1),
        for (int i = 1; i <= 24; i++)
          TrendSample(t0.add(const Duration(hours: 1) + Duration(hours: i)), 2),
      ];
      final s = TrendSeries.build(raw, maxBuckets: 120);

      expect(s.rawCount, 984);

      final late = s.samples.where((p) => p.t.isAfter(t0.add(const Duration(hours: 2))));
      expect(late, isNotEmpty);
      for (final p in late) {
        expect(p.v, closeTo(2, 1e-9),
            reason: 'point at ${p.t} carries a value recorded in the first hour');
      }
    });

    test('drops empty buckets rather than interpolating across a gap', () {
      final raw = <TrendSample>[
        for (int i = 0; i < 300; i++)
          TrendSample(t0.add(Duration(seconds: i)), 1),
        for (int i = 0; i < 300; i++)
          TrendSample(t0.add(Duration(days: 1, seconds: i)), 2),
      ];
      final s = TrendSeries.build(raw, maxBuckets: 100);

      final spanMs = s.end!.difference(s.start!).inMilliseconds;
      final midFrom = s.start!.add(Duration(milliseconds: spanMs ~/ 4));
      final midTo = s.start!.add(Duration(milliseconds: spanMs * 3 ~/ 4));

      expect(s.samples.where((p) => p.t.isAfter(midFrom) && p.t.isBefore(midTo)),
          isEmpty);
      expect(s.samples.first.v, closeTo(1, 1e-9));
      expect(s.samples.last.v, closeTo(2, 1e-9));
      // Only the two clusters survive, not one point per bucket.
      expect(s.samples.length, lessThan(10));
    });

    test('averages within a bucket', () {
      final raw = [
        for (int i = 0; i < 400; i++)
          TrendSample(t0.add(Duration(seconds: i)), i.isEven ? 0.0 : 10.0),
      ];
      final s = TrendSeries.build(raw, maxBuckets: 4);

      for (final p in s.samples) {
        expect(p.v, closeTo(5.0, 0.5));
      }
    });

    test('sorts unordered input', () {
      final raw = [
        TrendSample(t0.add(const Duration(hours: 2)), 3),
        TrendSample(t0, 1),
        TrendSample(t0.add(const Duration(hours: 1)), 2),
      ];
      final s = TrendSeries.build(raw);

      expect(s.samples.map((p) => p.v).toList(), [1, 2, 3]);
      expect(s.start, t0);
    });

    test('survives an empty list and a single point', () {
      expect(TrendSeries.build([]).isEmpty, isTrue);

      final one = TrendSeries.build([TrendSample(t0, 7)]);
      expect(one.samples.length, 1);
      expect(one.spanSeconds, 0);
    });

    test('collapses points that share one instant', () {
      final raw = [for (int i = 0; i < 500; i++) TrendSample(t0, i.toDouble())];
      final s = TrendSeries.build(raw, maxBuckets: 10);

      expect(s.samples.length, 1);
      expect(s.rawCount, 500);
      expect(s.samples.single.v, closeTo(249.5, 1e-9));
    });
  });

  group('axisTicks', () {
    test('spans the window end to end', () {
      final s = TrendSeries.build([
        TrendSample(t0, 1),
        TrendSample(t0.add(const Duration(hours: 6)), 2),
      ]);
      final ticks = s.axisTicks(4);

      expect(ticks.length, 4);
      expect(ticks.first, t0);
      expect(ticks.last, t0.add(const Duration(hours: 6)));
      for (int i = 1; i < ticks.length; i++) {
        expect(ticks[i].isAfter(ticks[i - 1]), isTrue);
      }
    });

    test('degenerate windows do not produce duplicate ticks', () {
      final s = TrendSeries.build([TrendSample(t0, 1)]);
      expect(s.axisTicks(4), [t0]);
      expect(TrendSeries.empty.axisTicks(4), isEmpty);
    });
  });

  group('ChartDate', () {
    test('picks clock time for short windows and dates for long ones', () {
      final t = DateTime(2026, 10, 27, 14, 5);
      expect(ChartDate.tick(t, 3600), '14:05');
      expect(ChartDate.tick(t, 86400 * 7), '27 Oct');
      expect(ChartDate.tick(t, 86400 * 400), '27 Oct 26');
    });

    test('pads single digits', () {
      expect(ChartDate.hm(DateTime(2026, 1, 2, 3, 4)), '03:04');
      expect(ChartDate.dayMonth(DateTime(2026, 1, 2)), '2 Jan');
    });

    test('collapses a same-day range to one date', () {
      final a = DateTime(2026, 10, 27, 9, 12);
      final b = DateTime(2026, 10, 27, 14, 5);
      expect(ChartDate.range(a, b), '27 Oct  09:12 – 14:05');
    });

    test('shows both dates when the range crosses days', () {
      final a = DateTime(2026, 10, 21, 9, 12);
      final b = DateTime(2026, 10, 27, 14, 5);
      expect(ChartDate.range(a, b), '21 Oct 09:12 – 27 Oct 14:05');
    });
  });
}
