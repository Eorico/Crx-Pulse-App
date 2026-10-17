import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../core/sensor_icons.dart';
import '../../core/firmware_spec.dart';
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
Color _darken(Color c, [double amt = 0.22]) => Color.lerp(c, Colors.black, amt)!;

class LocalAnalyticsScreen extends StatefulWidget {
  const LocalAnalyticsScreen({super.key});

  @override
  State<LocalAnalyticsScreen> createState() => _LocalAnalyticsScreenState();
}

class _LocalAnalyticsScreenState extends State<LocalAnalyticsScreen> {
  int _hoursBack = 24;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocalAnalyticsProvider>().fetchHistory(hoursBack: _hoursBack);
    });
  }

  void _changeRange(int hours) {
    setState(() => _hoursBack = hours);
    context.read<LocalAnalyticsProvider>().fetchHistory(hoursBack: hours);
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
    final metrics = <_MetricSpec>[
      _MetricSpec(
        title: 'pH Level', unit: '', decimals: 2, color: const Color(0xFF3B82F6),
        icon: LucideIcons.droplets, assetIcon: SensorIcons.ph, select: (p) => p.ph,
        zones: const [
          _Zone('Low', Color(0xFFF59E0B)),
          _Zone('Optimal', Color(0xFF22C55E)),
          _Zone('High', Color(0xFFEF4444)),
        ],
        zoneOf: (v) => v < FirmwareSpec.phSafeMin
            ? 0
            : (v <= FirmwareSpec.phSafeMax ? 1 : 2),
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
        zoneOf: (v) => v < FirmwareSpec.ammoniaSafeMax
            ? 0
            : (v < FirmwareSpec.ammoniaWarningMax ? 1 : 2),
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
        zoneOf: (v) => v <= FirmwareSpec.turbidityClearMax
            ? 0
            : (v <= FirmwareSpec.turbiditySlightlyMax
                ? 1
                : (v <= FirmwareSpec.turbidityTurbidMax ? 2 : 3)),
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
        zoneOf: (v) => v < FirmwareSpec.waterTempSafeMinC
            ? 0
            : (v <= FirmwareSpec.waterTempSafeMaxC ? 1 : 2),
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
        zoneOf: (v) => v < FirmwareSpec.coolingStartC
            ? 0
            : (v < FirmwareSpec.coolingMaxC ? 1 : 2),
      ),
    ];

    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: FadeIn(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => analytics.fetchHistory(hoursBack: _hoursBack),
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
                    const SizedBox(height: 20),
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
                                  history: analytics.history, spec: m),
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
  final int Function(double) zoneOf;
  const _MetricSpec({
    required this.title, required this.unit, required this.decimals,
    required this.color, required this.icon, required this.assetIcon, required this.select,
    required this.zones, required this.zoneOf,
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
        Text('No history yet', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('Readings are logged automatically about once a minute while connected', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ]),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  final int hoursBack;
  final ValueChanged<int> onChanged;
  const _RangeSelector({required this.hoursBack, required this.onChanged});

  static const _ranges = [(label: '24H', hours: 24), (label: '7D', hours: 168), (label: '30D', hours: 720)];

  @override
  Widget build(BuildContext context) {
    return Row(
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
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
    );
  }
}

// ───────────────────────── metric card ─────────────────────────

class _MetricAnalyticsCard extends StatelessWidget {
  final List<SensorHistoryPoint> history;
  final _MetricSpec spec;
  const _MetricAnalyticsCard({required this.history, required this.spec});

  @override
  Widget build(BuildContext context) {
    final values = <double>[];
    for (final p in history) {
      final v = spec.select(p);
      if (v != null) values.add(v);
    }

    final counts = List<int>.filled(spec.zones.length, 0);
    for (final v in values) {
      counts[spec.zoneOf(v).clamp(0, spec.zones.length - 1)]++;
    }
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

          const _ChartLabel('Trend'),
          const SizedBox(height: 8),
          _ClayWell(
            height: 160,
            // The ribbon draws itself left-to-right on first paint, so
            // the trend is read as a trend rather than appearing whole.
            child: values.length < 2
                ? const _NoData()
                : DrawIn(
                    duration: const Duration(milliseconds: 1100),
                    builder: (context, t) => CustomPaint(
                      painter: _Area3DPainter(
                          values: values, color: spec.color, progress: t),
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
/// wall and a lit top ribbon.
class _Area3DPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  /// 0 → 1 draw-in progress: the ribbon is revealed left-to-right, so
  /// the trend is traced out in time order the way it was recorded.
  final double progress;

  _Area3DPainter({required this.values, required this.color, this.progress = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || progress <= 0) return;
    const depthX = 14.0, depthY = 12.0;
    const topPad = depthY + 6, botPad = 10.0;
    final baseY = size.height - botPad;
    final usableH = baseY - topPad;
    final usableW = size.width - depthX;

    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);

    // Reveal by clipping rather than by shortening the paths: the
    // geometry below is computed once, at its final shape, so the line
    // never wobbles as it is drawn in.
    if (progress < 1.0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
    }

    Offset front(int i) {
      final x = usableW * i / (values.length - 1);
      final y = baseY - ((values[i] - minV) / span) * usableH;
      return Offset(x, y);
    }
    Offset back(int i) => front(i).translate(depthX, -depthY);

    // front wall (down to baseline)
    final wall = Path()..moveTo(front(0).dx, front(0).dy);
    for (int i = 1; i < values.length; i++) {
      wall.lineTo(front(i).dx, front(i).dy);
    }
    wall..lineTo(front(values.length - 1).dx, baseY)..lineTo(front(0).dx, baseY)..close();
    canvas.drawPath(wall, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.12)],
    ).createShader(Rect.fromLTWH(0, topPad, size.width, usableH)));

    // top ribbon (front edge → back edge)
    final ribbon = Path()..moveTo(front(0).dx, front(0).dy);
    for (int i = 1; i < values.length; i++) {
      ribbon.lineTo(front(i).dx, front(i).dy);
    }
    for (int i = values.length - 1; i >= 0; i--) {
      ribbon.lineTo(back(i).dx, back(i).dy);
    }
    ribbon.close();
    canvas.drawPath(ribbon, Paint()..color = _lighten(color, 0.18));

    // back edge + front edge strokes
    final backStroke = Path()..moveTo(back(0).dx, back(0).dy);
    for (int i = 1; i < values.length; i++) {
      backStroke.lineTo(back(i).dx, back(i).dy);
    }
    canvas.drawPath(backStroke, Paint()..color = _darken(color, 0.1)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    final frontStroke = Path()..moveTo(front(0).dx, front(0).dy);
    for (int i = 1; i < values.length; i++) {
      frontStroke.lineTo(front(i).dx, front(i).dy);
    }
    canvas.drawPath(frontStroke, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5);

    if (progress < 1.0) canvas.restore();

    // min / max guide labels — outside the clip so they stay legible
    // for the whole draw-in.
    final maxL = _label(maxV.toStringAsFixed(1), size: 9, color: AppColors.textMuted);
    maxL.paint(canvas, const Offset(0, topPad - depthY));
    final minL = _label(minV.toStringAsFixed(1), size: 9, color: AppColors.textMuted);
    minL.paint(canvas, Offset(0, baseY - minL.height));
  }

  @override
  bool shouldRepaint(covariant _Area3DPainter old) =>
      old.values != values || old.color != color || old.progress != progress;
}
