import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../services/local_analytics_provider.dart';
import '../../widgets/minimal_gif_header.dart';
import '../../widgets/fade_in.dart';

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

    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: FadeIn(
          child: RefreshIndicator(
            onRefresh: () => analytics.fetchHistory(hoursBack: _hoursBack),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              children: [
                const MinimalGifHeader(title: 'Analytics', subtitle: 'Trends over time'),
                const SizedBox(height: 20),
                _RangeSelector(hoursBack: _hoursBack, onChanged: _changeRange),
                const SizedBox(height: 20),

                if (analytics.isLoading)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
                else if (analytics.history.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
                    child: const Column(children: [
                      Icon(LucideIcons.barChart3, color: AppColors.textMuted, size: 40),
                      SizedBox(height: 12),
                      Text('No history yet', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('Readings are logged automatically about once a minute while connected', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ]),
                  )
                else ...[
                  _TrendCard(
                    title: 'pH Level', color: const Color(0xFF3B82F6), unit: '',
                    spots: _spotsFor(analytics.history, (p) => p.ph),
                  ),
                  const SizedBox(height: 16),
                  _TrendCard(
                    title: 'Ammonia', color: const Color(0xFFF59E0B), unit: ' ppm',
                    spots: _spotsFor(analytics.history, (p) => p.ammonia),
                  ),
                  const SizedBox(height: 16),
                  _TrendCard(
                    title: 'Turbidity', color: const Color(0xFF8B5CF6), unit: ' NTU',
                    spots: _spotsFor(analytics.history, (p) => p.turbidity),
                  ),
                  const SizedBox(height: 16),
                  _TrendCard(
                    title: 'Water Temperature', color: AppColors.primary, unit: '°C',
                    spots: _spotsFor(analytics.history, (p) => p.waterTempC),
                  ),
                  const SizedBox(height: 16),
                  _TrendCard(
                    title: 'Housing Temperature', color: const Color(0xFFEF4444), unit: '°C',
                    spots: _spotsFor(analytics.history, (p) => p.ambientTempC),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<FlSpot> _spotsFor(List<SensorHistoryPoint> history, double? Function(SensorHistoryPoint) selector) {
    final spots = <FlSpot>[];
    for (int i = 0; i < history.length; i++) {
      final v = selector(history[i]);
      if (v != null) spots.add(FlSpot(i.toDouble(), v));
    }
    return spots;
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
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onChanged(r.hours),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: selected ? [] : AppShadows.card,
              ),
              child: Text(r.label, style: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final String title;
  final Color color;
  final String unit;
  final List<FlSpot> spots;
  const _TrendCard({required this.title, required this.color, required this.unit, required this.spots});

  @override
  Widget build(BuildContext context) {
    final latest = spots.isNotEmpty ? spots.last.y : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
              if (latest != null)
                Text('${latest.toStringAsFixed(1)}$unit', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: color)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: spots.isEmpty
                ? const Center(child: Text('No data in this range', style: TextStyle(color: AppColors.textMuted, fontSize: 12)))
                : LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => AppColors.textPrimary,
                          getTooltipItems: (touchedSpots) => touchedSpots
                              .map((s) => LineTooltipItem('${s.y.toStringAsFixed(2)}$unit', const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)))
                              .toList(),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: color,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
