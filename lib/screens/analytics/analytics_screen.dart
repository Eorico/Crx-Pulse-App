import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../core/sensor_icons.dart';
import '../../core/firmware_spec.dart';
import '../../core/metric_bands.dart';
import '../../core/trend_series.dart';
import '../../services/local_analytics_provider.dart';
import '../../widgets/minimal_gif_header.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/motion.dart';
import '../../widgets/sticky_header_delegate.dart';

/// Analytics tab — each metric (pH, Ammonia, Turbidity, Water Temp,
/// Housing Temp) gets THREE genuinely 3D charts, hand-drawn with a
/// CustomPainter (fl_chart can only fake depth):
///   • 3D Area ribbon — the trend over the window, extruded into depth.
///   • 3D Pie         — a real tilted disc with a visible side wall.
///   • 3D Bar         — extruded boxes with lit top + shaded side faces.
/// All sit in inset clay "wells" to stay consistent with the app.

// ───────────────────────── color helpers ─────────────────────────
Color _lighten(Color c, [double amt = 0.22]) => Color.lerp(c, Colors.white, amt)!;

/// `1284` -> `1,284`. Reading counts run into the tens of thousands
/// once the cloud history is in play, and unseparated digits at 11pt
/// are hard to size up at a glance.
String _grouped(int n) {
  final digits = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return buf.toString();
}
Color _darken(Color c, [double amt = 0.22]) => Color.lerp(c, Colors.black, amt)!;

class LocalAnalyticsScreen extends StatefulWidget {
  const LocalAnalyticsScreen({super.key});

  @override
  State<LocalAnalyticsScreen> createState() => _LocalAnalyticsScreenState();
}

class _LocalAnalyticsScreenState extends State<LocalAnalyticsScreen> {
  /// Null means "everything on record", not "nothing".
  int? _hoursBack = 24;

  /// Handed to the provider so the database can count the zone
  /// distribution itself. Same objects the cards classify with, so
  /// there is one definition of every boundary.
  Map<String, MetricBands> get _bands =>
      {for (final m in _metricSpecs()) m.bands.column: m.bands};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<LocalAnalyticsProvider>()
          .fetchHistory(hoursBack: _hoursBack, bands: _bands);
    });
  }

  void _changeRange(int? hours) {
    setState(() => _hoursBack = hours);
    context
        .read<LocalAnalyticsProvider>()
        .fetchHistory(hoursBack: hours, bands: _bands);
  }

  @override
  Widget build(BuildContext context) {
    final analytics = context.watch<LocalAnalyticsProvider>();

    // Zone boundaries come from FirmwareSpec, so the distribution
    // charts describe the SAME bands the device and the sensor cards
    // use. Turbidity in particular now has the firmware's own four
    // bands (Clear / Slightly Turbid / Turbid / Highly Turbid at
    // 19.9 / 48.5 / 78.6 %) instead of invented 25 / 60 % cuts, and
    // Housing Temperature is split at the two points where the cooling
    // fan actually changes behaviour rather than at 35 / 45 °C.
    final metrics = _metricSpecs();
    return _buildBody(context, analytics, metrics);
  }

  List<_MetricSpec> _metricSpecs() {
    return <_MetricSpec>[
      _MetricSpec(
        title: 'pH Level', unit: '', decimals: 2, color: const Color(0xFF3B82F6),
        icon: LucideIcons.droplets, assetIcon: SensorIcons.ph, select: (p) => p.ph,
        zones: const [
          _Zone('Low', Color(0xFFF59E0B)),
          _Zone('Optimal', Color(0xFF22C55E)),
          _Zone('High', Color(0xFFEF4444)),
        ],
        // 6.5 is the bottom of SAFE, so it belongs to Optimal: strict.
        // 8.5 is the TOP of safe, so it belongs to Optimal: inclusive.
        bands: const MetricBands(
          column: 'ph',
          cuts: [FirmwareSpec.phSafeMin, FirmwareSpec.phSafeMax],
          strict: [true, false],
        ),
      ),
      _MetricSpec(
        title: 'Ammonia',
        unit: FirmwareSpec.ammoniaUnit,
        decimals: 2,
        color: const Color(0xFFF59E0B),
        icon: LucideIcons.flaskConical, assetIcon: SensorIcons.ammonia,
        select: (p) => p.ammonia,
        // The firmware's own Safe / Warning / Critical labels.
        zones: const [
          _Zone('Safe', Color(0xFF22C55E)),
          _Zone('Warning', Color(0xFFF59E0B)),
          _Zone('Critical', Color(0xFFEF4444)),
        ],
        bands: const MetricBands(
          column: 'ammonia',
          cuts: [FirmwareSpec.ammoniaSafeMax, FirmwareSpec.ammoniaWarningMax],
          strict: [true, true],
        ),
      ),
      _MetricSpec(
        title: 'Turbidity', unit: '%', decimals: 1, color: const Color(0xFF8B5CF6),
        icon: LucideIcons.waves, assetIcon: SensorIcons.turbidity,
        select: (p) => p.turbidity,
        zones: const [
          _Zone('Clear', Color(0xFF22C55E)),
          _Zone('Slightly', Color(0xFF84CC16)),
          _Zone('Turbid', Color(0xFFF59E0B)),
          _Zone('Highly', Color(0xFFEF4444)),
        ],
        // The standard reads "Clear: 0 -< 19.94%", so 19.94 is already
        // Slightly Turbid and that first cut is STRICT. The other two
        // are the TOP of their band, so they stay inclusive. This
        // matches TurbidityCalibration::statusOf in the firmware.
        bands: const MetricBands(
          column: 'turbidity',
          cuts: [
            FirmwareSpec.turbidityClearMax,
            FirmwareSpec.turbiditySlightlyMax,
            FirmwareSpec.turbidityTurbidMax,
          ],
          strict: [true, false, false],
        ),
      ),
      _MetricSpec(
        title: 'Water Temperature', unit: '°C', decimals: 1, color: AppColors.primary,
        icon: LucideIcons.thermometer, assetIcon: SensorIcons.waterTemp,
        select: (p) => p.waterTempC,
        zones: const [
          _Zone('Cool', Color(0xFF3B82F6)),
          _Zone('Optimal', Color(0xFF22C55E)),
          _Zone('Warm', Color(0xFFEF4444)),
        ],
        bands: const MetricBands(
          column: 'water_temp_c',
          cuts: [FirmwareSpec.waterTempSafeMinC, FirmwareSpec.waterTempSafeMaxC],
          strict: [true, false],
        ),
      ),
      _MetricSpec(
        title: 'Housing Temperature', unit: '°C', decimals: 1,
        color: const Color(0xFFEF4444),
        icon: LucideIcons.cpu, assetIcon: SensorIcons.housingTemp,
        select: (p) => p.ambientTempC,
        // Split at the firmware's cooling thresholds: fan off, fan
        // ramping, fan pegged at 100%.
        zones: const [
          _Zone('Fan off', Color(0xFF22C55E)),
          _Zone('Cooling', Color(0xFFF59E0B)),
          _Zone('Fan max', Color(0xFFEF4444)),
        ],
        bands: const MetricBands(
          column: 'ambient_temp_c',
          cuts: [FirmwareSpec.coolingStartC, FirmwareSpec.coolingMaxC],
          strict: [true, true],
        ),
      ),
    ];
  }

  Widget _buildBody(BuildContext context, LocalAnalyticsProvider analytics,
      List<_MetricSpec> metrics) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: FadeIn(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () =>
                analytics.fetchHistory(hoursBack: _hoursBack, bands: _bands),
            child: CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: StickyHeaderDelegate(
                    height: 76,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: MinimalGifHeader(title: 'Analytics', subtitle: '3D trends & distributions'),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                  sliver: SliverList.list(children: [
                    _RangeSelector(hoursBack: _hoursBack, onChanged: _changeRange),
                    const SizedBox(height: 12),
                    _SourceBanner(analytics: analytics),
                    const SizedBox(height: 8),
                    if (analytics.isLoading)
                      const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
                    else if (analytics.history.isEmpty)
                      const FadeSlideIn(beginScale: 0.94, from: Offset.zero, child: _EmptyState())
                    else
                      // Each metric card arrives in turn; its charts
                      // then draw themselves in (see _MetricAnalyticsCard).
                      ...FadeSlideIn.stagger(
                        [
                          for (final m in metrics)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: _MetricAnalyticsCard(
                                  history: analytics.history,
                                  spec: m,
                                  serverCounts: analytics.zoneCounts[m.bands.column]),
                            ),
                        ],
                        from: const Offset(0, 0.08),
                      ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── specs ─────────────────────────

class _Zone {
  final String label;
  final Color color;
  const _Zone(this.label, this.color);
}

class _MetricSpec {
  final String title;
  final String unit;
  final int decimals;
  final Color color;
  final IconData icon;
  final String assetIcon;
  final double? Function(SensorHistoryPoint) select;
  final List<_Zone> zones;

  /// Boundaries as data, so the exact same numbers can be sent to the
  /// `readings_zone_counts` SQL function. See [MetricBands].
  final MetricBands bands;

  const _MetricSpec({
    required this.title, required this.unit, required this.decimals,
    required this.color, required this.icon, required this.assetIcon, required this.select,
    required this.zones, required this.bands,
  });
}

// ───────────────────────── empty / range ─────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: AppColors.clayFill, borderRadius: BorderRadius.circular(AppRadius.card), boxShadow: AppShadows.clay),
      child: const Column(children: [
        Icon(LucideIcons.chartColumnBig, color: AppColors.textMuted, size: 40),
        SizedBox(height: 12),
        Text('No readings in this range', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('Your device records continuously once it is online. Try a wider range, or ALL.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ]),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  final int? hoursBack;
  final ValueChanged<int?> onChanged;
  const _RangeSelector({required this.hoursBack, required this.onChanged});

  // `All` has no cutoff — it reads the device's entire history out of
  // the readings table, not just a trailing window.
  static const _ranges = <({String label, int? hours})>[
    (label: '24H', hours: 24),
    (label: '7D', hours: 168),
    (label: '30D', hours: 720),
    (label: 'ALL', hours: null),
  ];

  @override
  Widget build(BuildContext context) {
    // Scrollable: a fourth chip takes the row close to the edge on a
    // narrow phone, and at large text scales past it.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
      children: _ranges.map((r) {
        final selected = r.hours == hoursBack;
        return Padding(
          padding: const EdgeInsets.only(right: 10),
          // Chips depress under the finger and the colour/shadow swap
          // animates, so switching range feels like pressing a real
          // button rather than repainting a label.
          child: PressableScale(
            onTap: () => onChanged(r.hours),
            child: AnimatedContainer(
              duration: AppMotion.normal,
              curve: AppMotion.smooth,
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.clayFill,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                boxShadow: selected ? AppShadows.claySoft : AppShadows.card,
              ),
              child: AnimatedDefaultTextStyle(
                duration: AppMotion.normal,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                child: Text(r.label),
              ),
            ),
          ),
        );
      }).toList(),
      ),
    );
  }
}

/// One line under the range chips saying where the charted readings
/// came from and how many there are.
///
/// It matters because the two sources are not equivalent: the cloud
/// holds every reading the device ever took, the local fallback holds
/// at most one a minute from while this phone was open. Without this
/// line a thin local chart is indistinguishable from a quiet device.
class _SourceBanner extends StatelessWidget {
  final LocalAnalyticsProvider analytics;
  const _SourceBanner({required this.analytics});

  @override
  Widget build(BuildContext context) {
    if (analytics.isLoading) return const SizedBox.shrink();

    final rows = analytics.history.length;
    final isLocal = analytics.source == HistorySource.local;

    final span = rows >= 2
        ? ChartDate.range(
            analytics.history.first.recordedAt, analytics.history.last.recordedAt)
        : (rows == 1 ? ChartDate.stamp(analytics.history.first.recordedAt) : null);

    final parts = <String>[
      '${_grouped(rows)} reading${rows == 1 ? '' : 's'}',
      if (span != null) span,
    ];

    final warn = isLocal || analytics.truncated;
    final color = warn ? const Color(0xFFB45309) : AppColors.textMuted;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isLocal ? LucideIcons.cloudOff : LucideIcons.database,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                parts.join('  ·  '),
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
              ),
              if (isLocal)
                Text(
                  analytics.diagnosis?.summary ??
                      "Showing this phone's local log — the cloud history is unavailable.",
                  style: TextStyle(fontSize: 10.5, color: color),
                ),
              if (isLocal && analytics.diagnosis?.fix != null)
                Text(
                  analytics.diagnosis!.fix!,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                ),
              if (analytics.truncated)
                Text(
                  'Only the most recent ${_grouped(LocalAnalyticsProvider.maxPoints)} readings in this range were loaded.',
                  style: TextStyle(fontSize: 10.5, color: color),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── metric card ─────────────────────────

class _MetricAnalyticsCard extends StatelessWidget {
  final List<SensorHistoryPoint> history;
  final _MetricSpec spec;

  /// Zone counts the database computed over the whole window, or null
  /// when the raw path ran and the card must count for itself.
  final List<int>? serverCounts;

  const _MetricAnalyticsCard({
    required this.history,
    required this.spec,
    this.serverCounts,
  });

  @override
  Widget build(BuildContext context) {
    final values = <double>[];
    final samples = <TrendSample>[];
    for (final p in history) {
      final v = spec.select(p);
      if (v == null) continue;
      values.add(v);
      samples.add(TrendSample(p.recordedAt, v));
    }

    // Thinned for painting only. The counts below still come from
    // every raw reading, so the distribution stays exact however long
    // the window is.
    final series = TrendSeries.build(samples);

    // Exact counts over every reading in the window when the database
    // did the counting; otherwise count what was transferred. Both use
    // spec.bands, so the two agree on where every boundary falls.
    List<int> countLocally() {
      final c = List<int>.filled(spec.zones.length, 0);
      for (final v in values) {
        c[spec.bands.zoneOf(v).clamp(0, spec.zones.length - 1)]++;
      }
      return c;
    }

    final counts = serverCounts ?? countLocally();
    final total = counts.fold<int>(0, (a, b) => a + b);
    final latest = values.isNotEmpty ? values.last : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.clayFill, borderRadius: BorderRadius.circular(AppRadius.card), boxShadow: AppShadows.clay),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.clayFill,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppShadows.claySoft,
                ),
                // The metric's animated sensor GIF, matching the cards
                // on the dashboard and management screens.
                child: Image.asset(spec.assetIcon, fit: BoxFit.contain),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(spec.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary))),
              if (latest != null)
                // The headline figure counts to each new reading.
                AnimatedNumber(
                  value: latest,
                  decimals: spec.decimals,
                  suffix: spec.unit,
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 18, color: spec.color),
                ),
            ],
          ),
          const SizedBox(height: 18),

          Row(
            children: [
              const _ChartLabel('Trend'),
              const Spacer(),
              if (series.start != null && series.end != null)
                Text(
                  series.rawCount >= 2
                      ? ChartDate.range(series.start!, series.end!)
                      : ChartDate.stamp(series.start!),
                  style: const TextStyle(
                      fontSize: 9.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _ClayWell(
            // Taller than the other two wells: this one now carries a
            // dated x-axis under the plot.
            height: 184,
            // The ribbon draws itself left-to-right on first paint, so
            // the trend is read as a trend rather than appearing whole.
            child: series.samples.length < 2
                ? const _NoData()
                : DrawIn(
                    duration: const Duration(milliseconds: 1100),
                    builder: (context, t) => CustomPaint(
                      painter: _Area3DPainter(
                          series: series,
                          color: spec.color,
                          decimals: spec.decimals,
                          progress: t),
                    ),
                  ),
          ),
          const SizedBox(height: 18),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _ChartLabel('Distribution'),
                  const SizedBox(height: 8),
                  _ClayWell(
                    height: 160,
                    // The disc sweeps round from the back-left as it
                    // fills in.
                    child: total == 0
                        ? const _NoData()
                        : DrawIn(
                            delay: const Duration(milliseconds: 160),
                            builder: (context, t) => CustomPaint(
                              painter: _Pie3DPainter(
                                  counts: counts,
                                  zones: spec.zones,
                                  total: total,
                                  progress: t),
                            ),
                          ),
                  ),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _ChartLabel('By Zone'),
                  const SizedBox(height: 8),
                  _ClayWell(
                    height: 160,
                    // Boxes grow up out of the baseline.
                    child: total == 0
                        ? const _NoData()
                        : DrawIn(
                            delay: const Duration(milliseconds: 240),
                            builder: (context, t) => CustomPaint(
                              painter: _Bar3DPainter(
                                  counts: counts, zones: spec.zones, progress: t),
                            ),
                          ),
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Wrap(
            spacing: 14, runSpacing: 6,
            children: [
              for (int i = 0; i < spec.zones.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 11, height: 11, decoration: BoxDecoration(color: spec.zones[i].color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${spec.zones[i].label} (${counts[i]})', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                ]),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartLabel extends StatelessWidget {
  final String text;
  const _ChartLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textMuted));
}

class _NoData extends StatelessWidget {
  const _NoData();
  @override
  Widget build(BuildContext context) => const Center(child: Text('No data in this range', style: TextStyle(color: AppColors.textMuted, fontSize: 11)));
}

class _ClayWell extends StatelessWidget {
  final double height;
  final Widget child;
  const _ClayWell({required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF4F6F1), borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.clayPressed),
      child: SizedBox.expand(child: child),
    );
  }
}

// ═══════════════════════ 3D PAINTERS ═══════════════════════

TextPainter _label(String s, {required double size, required Color color, FontWeight weight = FontWeight.w700}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight)),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp;
}

/// 3D extruded bar chart — each zone is a box with a lit top face and a
/// shaded right side face.
class _Bar3DPainter extends CustomPainter {
  final List<int> counts;
  final List<_Zone> zones;

  /// 0 → 1 draw-in progress: bars grow up out of the baseline.
  final double progress;

  _Bar3DPainter({required this.counts, required this.zones, this.progress = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final n = counts.length;
    if (n == 0) return;
    final maxCount = counts.reduce(math.max);
    final maxV = (maxCount == 0 ? 1 : maxCount).toDouble();

    const depthX = 10.0, depthY = 8.0;
    const labelH = 20.0, topPad = 18.0;
    final baseY = size.height - labelH;
    final usableH = baseY - topPad;
    final slot = (size.width - depthX) / n;
    final barW = slot * 0.56;

    // ground line
    final ground = Paint()..color = Colors.black.withValues(alpha: 0.06)..strokeWidth = 1;
    canvas.drawLine(Offset(0, baseY + 0.5), Offset(size.width, baseY + 0.5), ground);

    for (int i = 0; i < n; i++) {
      final c = zones[i].color;
      // Each bar is staggered slightly behind the one to its left, so
      // the group rises in sequence rather than as a block.
      final lead = (progress * n - i).clamp(0.0, 1.0);
      final h = (counts[i] / maxV) * usableH * lead;
      final l = i * slot + (slot - barW) / 2;
      final top = baseY - h;
      if (lead <= 0) continue;

      final front = Rect.fromLTRB(l, top, l + barW, baseY);
      final frontPaint = Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [_lighten(c, 0.12), c],
      ).createShader(front);

      // top face (parallelogram)
      final topFace = Path()
        ..moveTo(l, top)
        ..lineTo(l + depthX, top - depthY)
        ..lineTo(l + barW + depthX, top - depthY)
        ..lineTo(l + barW, top)
        ..close();
      // right side face
      final sideFace = Path()
        ..moveTo(l + barW, top)
        ..lineTo(l + barW + depthX, top - depthY)
        ..lineTo(l + barW + depthX, baseY - depthY)
        ..lineTo(l + barW, baseY)
        ..close();

      canvas.drawPath(sideFace, Paint()..color = _darken(c, 0.28));
      canvas.drawPath(topFace, Paint()..color = _lighten(c, 0.30));
      if (h > 0) canvas.drawRect(front, frontPaint);

      // count label above the box
      final cl = _label('${counts[i]}', size: 11, color: AppColors.textPrimary, weight: FontWeight.w800);
      cl.paint(canvas, Offset(l + barW / 2 - cl.width / 2 + depthX / 2, top - depthY - cl.height - 2));

      // zone label on the baseline
      final zl = _label(zones[i].label, size: 9, color: AppColors.textMuted);
      zl.paint(canvas, Offset(l + barW / 2 - zl.width / 2, baseY + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _Bar3DPainter old) =>
      old.counts != counts || old.progress != progress;
}

/// 3D pie — a tilted disc (ellipse) with a visible extruded side wall on
/// the front-facing rim.
class _Pie3DPainter extends CustomPainter {
  final List<int> counts;
  final List<_Zone> zones;
  final int total;

  /// 0 → 1 draw-in progress: the disc sweeps round as it fills.
  final double progress;

  _Pie3DPainter({
    required this.counts,
    required this.zones,
    required this.total,
    this.progress = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total == 0 || progress <= 0) return;
    const depth = 16.0;
    final cx = size.width / 2;
    final cy = size.height / 2 - depth / 2;
    final r = math.min(size.width, size.height) / 2 - 16;
    final ry = r * 0.56; // tilt

    Offset pt(double a, [double dy = 0]) => Offset(cx + r * math.cos(a), cy + ry * math.sin(a) + dy);

    // Slice angle ranges (start at the back-left, sweep clockwise).
    // Multiplying each sweep by `progress` makes the whole disc wipe
    // round from that starting angle as it draws in.
    double a = -math.pi;
    final ranges = <List<double>>[];
    for (int i = 0; i < counts.length; i++) {
      final sweep = (counts[i] / total) * 2 * math.pi * progress;
      ranges.add([a, a + sweep]);
      a += sweep;
    }

    // 1) side walls for the FRONT rim (where sin(a) > 0 → lower/front).
    for (int i = 0; i < counts.length; i++) {
      if (counts[i] == 0) continue;
      final s = ranges[i][0], e = ranges[i][1];
      final fs = math.max(s, 0.0), fe = math.min(e, math.pi);
      if (fe <= fs) continue; // this slice isn't on the front rim
      final wall = Path()..moveTo(pt(fs).dx, pt(fs).dy);
      const steps = 24;
      for (int k = 1; k <= steps; k++) {
        final ang = fs + (fe - fs) * k / steps;
        wall.lineTo(pt(ang).dx, pt(ang).dy);
      }
      for (int k = steps; k >= 0; k--) {
        final ang = fs + (fe - fs) * k / steps;
        wall.lineTo(pt(ang, depth).dx, pt(ang, depth).dy);
      }
      wall.close();
      canvas.drawPath(wall, Paint()..color = _darken(zones[i].color, 0.30));
    }

    // 2) top faces (the lid), drawn after walls so the lid sits on top.
    for (int i = 0; i < counts.length; i++) {
      if (counts[i] == 0) continue;
      final s = ranges[i][0], e = ranges[i][1];
      final top = Path()..moveTo(cx, cy);
      const steps = 40;
      for (int k = 0; k <= steps; k++) {
        final ang = s + (e - s) * k / steps;
        top.lineTo(pt(ang).dx, pt(ang).dy);
      }
      top.close();
      canvas.drawPath(top, Paint()..color = zones[i].color);
      canvas.drawPath(top, Paint()..color = _lighten(zones[i].color, 0.10)..style = PaintingStyle.stroke..strokeWidth = 1);

      // percentage label at the slice mid-angle
      final mid = (s + e) / 2;
      final lx = cx + (r * 0.6) * math.cos(mid);
      final ly = cy + (ry * 0.6) * math.sin(mid);
      final pct = ((counts[i] / total) * 100).round();
      // Labels only once the disc has finished sweeping, so they do not
      // slide around mid-animation.
      if (pct >= 8 && progress > 0.98) {
        final tl = _label('$pct%', size: 10, color: Colors.white, weight: FontWeight.w800);
        tl.paint(canvas, Offset(lx - tl.width / 2, ly - tl.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Pie3DPainter old) =>
      old.counts != counts || old.total != total || old.progress != progress;
}

/// 3D area ribbon — the trend line extruded back into depth, with a front
/// wall and a lit top ribbon, drawn against a dated time axis.
///
/// X is *time*, not list position. Plotting by index made an outage
/// look like a normal step between readings; now a gap in the record
/// shows as a gap, and the ticks below say which days and hours the
/// curve covers.
class _Area3DPainter extends CustomPainter {
  final TrendSeries series;
  final Color color;
  final int decimals;

  /// 0 → 1 draw-in progress: the ribbon is revealed left-to-right, so
  /// the trend is traced out in time order the way it was recorded.
  final double progress;

  _Area3DPainter({
    required this.series,
    required this.color,
    this.decimals = 1,
    this.progress = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pts = series.samples;
    if (pts.length < 2 || progress <= 0) return;
    const depthX = 14.0, depthY = 12.0;
    // The bottom strip belongs to the date ticks.
    const topPad = depthY + 6, axisH = 26.0;
    final baseY = size.height - axisH;
    final usableH = baseY - topPad;
    final usableW = size.width - depthX;

    final minV = series.minV;
    final maxV = series.maxV;
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);

    final t0 = pts.first.t.millisecondsSinceEpoch;
    final tSpan = pts.last.t.millisecondsSinceEpoch - t0;

    double xAt(DateTime t) => tSpan <= 0
        ? 0.0
        : usableW * (t.millisecondsSinceEpoch - t0) / tSpan;

    // ── dated axis, drawn first so the ribbon sits over the grid ──
    final ticks = series.axisTicks(4);
    final gridPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(0, baseY + 0.5), Offset(size.width, baseY + 0.5), gridPaint);

    for (int i = 0; i < ticks.length; i++) {
      final x = xAt(ticks[i]);
      canvas.drawLine(Offset(x, topPad - depthY), Offset(x, baseY), gridPaint);

      final tl = _label(ChartDate.tick(ticks[i], series.spanSeconds),
          size: 8.5, color: AppColors.textMuted, weight: FontWeight.w600);
      // Nudge the end labels inward so neither runs off the well.
      double lx = x - tl.width / 2;
      if (i == 0) lx = math.max(0, lx);
      if (i == ticks.length - 1) lx = math.min(size.width - tl.width, lx);
      tl.paint(canvas, Offset(lx, baseY + 5));
    }

    // Reveal by clipping rather than by shortening the paths: the
    // geometry below is computed once, at its final shape, so the line
    // never wobbles as it is drawn in.
    if (progress < 1.0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
    }

    Offset front(int i) {
      final y = baseY - ((pts[i].v - minV) / span) * usableH;
      return Offset(xAt(pts[i].t), y);
    }
    Offset back(int i) => front(i).translate(depthX, -depthY);
    // front wall (down to baseline)
    final wall = Path()..moveTo(front(0).dx, front(0).dy);
    for (int i = 1; i < pts.length; i++) {
      wall.lineTo(front(i).dx, front(i).dy);
    }
    wall..lineTo(front(pts.length - 1).dx, baseY)..lineTo(front(0).dx, baseY)..close();
    canvas.drawPath(wall, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.12)],
    ).createShader(Rect.fromLTWH(0, topPad, size.width, usableH)));

    // top ribbon (front edge → back edge)
    final ribbon = Path()..moveTo(front(0).dx, front(0).dy);
    for (int i = 1; i < pts.length; i++) {
      ribbon.lineTo(front(i).dx, front(i).dy);
    }
    for (int i = pts.length - 1; i >= 0; i--) {
      ribbon.lineTo(back(i).dx, back(i).dy);
    }
    ribbon.close();
    canvas.drawPath(ribbon, Paint()..color = _lighten(color, 0.18));

    // back edge + front edge strokes
    final backStroke = Path()..moveTo(back(0).dx, back(0).dy);
    for (int i = 1; i < pts.length; i++) {
      backStroke.lineTo(back(i).dx, back(i).dy);
    }
    canvas.drawPath(backStroke, Paint()..color = _darken(color, 0.1)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    final frontStroke = Path()..moveTo(front(0).dx, front(0).dy);
    for (int i = 1; i < pts.length; i++) {
      frontStroke.lineTo(front(i).dx, front(i).dy);
    }
    canvas.drawPath(frontStroke, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5);

    if (progress < 1.0) canvas.restore();

    // min / max guide labels — outside the clip so they stay legible
    // for the whole draw-in.
    final maxL = _label(maxV.toStringAsFixed(decimals), size: 9, color: AppColors.textMuted);
    maxL.paint(canvas, const Offset(0, topPad - depthY));
    final minL = _label(minV.toStringAsFixed(decimals), size: 9, color: AppColors.textMuted);
    minL.paint(canvas, Offset(0, baseY - minL.height));
  }

  @override
  bool shouldRepaint(covariant _Area3DPainter old) =>
      !identical(old.series, series) ||
      old.color != color ||
      old.decimals != decimals ||
      old.progress != progress;
}
