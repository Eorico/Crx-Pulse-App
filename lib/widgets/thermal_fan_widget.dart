import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/theme.dart';
import '../core/fan_speed_util.dart';
import '../services/floating_widget_position_provider.dart';

const double _widgetSize = 48;
const double _expandedWidth = 176;
const double _dragThreshold = 6;
const double _collapsedOpacity = 0.35;
const double _expandedOpacity = 1.0;

/// Exact port of components/thermal-fan-widget.tsx - same collapsed/
/// expanded sizing, same colors, same edge-snapping drag behavior,
/// same tap-vs-drag distinction decided on release (never assumed
/// on touch-down, so a real drag never accidentally opens it).
///
/// IMPROVEMENT over the original, per explicit request: spinning now
/// uses REAL fan telemetry (fanActive/fanDutyPercent from the ESP32)
/// when available, falling back to the same temperature-estimated
/// speed the original always used only when real fan data hasn't
/// arrived yet. This means the icon "definitely spins if it tracks
/// that the fan is actually spinning" - not just an estimate.
class ThermalFanWidget extends StatefulWidget {
  final double? waterTempC;
  final double? ambientTempC;
  final bool isLive;
  final bool? fanActive;
  final int? fanDutyPercent;

  const ThermalFanWidget({
    super.key,
    required this.waterTempC,
    required this.ambientTempC,
    required this.isLive,
    this.fanActive,
    this.fanDutyPercent,
  });

  @override
  State<ThermalFanWidget> createState() => _ThermalFanWidgetState();
}

class _ThermalFanWidgetState extends State<ThermalFanWidget> with TickerProviderStateMixin {
  bool _expanded = false;
  bool _wasDragged = false;
  Offset _dragStartPosition = Offset.zero;

  late AnimationController _opacityController;
  late AnimationController _scaleController;
  AnimationController? _spinController;

  @override
  void initState() {
    super.initState();
    _opacityController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220), value: 0,
    );
    _scaleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _restartSpin();
  }

  @override
  void didUpdateWidget(ThermalFanWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentFanPercent(oldWidget) != _currentFanPercent(widget) || oldWidget.isLive != widget.isLive) {
      _restartSpin();
    }
  }

  /// Real fan telemetry wins when available (non-null) - this is the
  /// "definitely spins if it tracks the fan is actually spinning"
  /// requirement. Falls back to the temperature-based estimate only
  /// when real data hasn't arrived, matching the original's only
  /// available behavior.
  int _currentFanPercent(ThermalFanWidget w) {
    if (w.fanActive == true && w.fanDutyPercent != null) return w.fanDutyPercent!;
    if (w.fanActive == false) return 0;
    return computeFanSpeed(w.ambientTempC).percent;
  }

  bool get _isUsingRealFanState => widget.fanActive != null;

  void _restartSpin() {
    _spinController?.dispose();
    _spinController = null;

    final shouldSpin = widget.isLive && (widget.fanActive ?? true) && _currentFanPercent(widget) > 0;
    if (!shouldSpin) {
      setState(() {});
      return;
    }

    final durationMs = fanPercentToSpinDurationMs(_currentFanPercent(widget));
    _spinController = AnimationController(vsync: this, duration: Duration(milliseconds: durationMs))
      ..repeat();
    setState(() {});
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _opacityController.forward();
      _scaleController.forward();
    } else {
      _opacityController.reverse();
      _scaleController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final positionProvider = context.watch<FloatingWidgetPositionProvider>();
    final screenSize = MediaQuery.of(context).size;
    positionProvider.initializeIfNeeded(screenSize, _widgetSize);

    final fanSpeed = widget.isLive ? _currentFanPercent(widget) : 0;
    final isHot = widget.isLive && widget.ambientTempC != null && widget.ambientTempC! >= 34.0;
    final fanColor = !widget.isLive ? const Color(0xFF9CA3AF) : (isHot ? const Color(0xFFEF4444) : AppColors.primary);

    return Positioned(
      left: positionProvider.position.dx,
      top: positionProvider.position.dy,
      child: GestureDetector(
        onPanStart: (details) {
          _dragStartPosition = details.globalPosition;
          _wasDragged = false;
        },
        onPanUpdate: (details) {
          if ((details.globalPosition - _dragStartPosition).distance > _dragThreshold) {
            _wasDragged = true;
          }
          positionProvider.updatePosition(positionProvider.position + details.delta);
        },
        onPanEnd: (_) {
          if (!_wasDragged) {
            _toggleExpanded();
          }
          _snapToNearestEdge(positionProvider, screenSize);
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_opacityController, _scaleController]),
          builder: (context, child) {
            final opacity = _collapsedOpacity + (_expandedOpacity - _collapsedOpacity) * _opacityController.value;
            final scale = 1.0 + 0.04 * _scaleController.value;
            return Opacity(
              opacity: opacity,
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isHot ? const Color(0xFFFCA5A5) : AppColors.border),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.15), offset: const Offset(0, 4), blurRadius: 10),
              ],
            ),
            child: _expanded ? _buildExpanded(fanColor, isHot, fanSpeed) : _buildCollapsed(fanColor),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsed(Color fanColor) {
    return SizedBox(
      width: _widgetSize,
      height: _widgetSize,
      child: Center(child: _spinningFan(fanColor, 22)),
    );
  }

  Widget _buildExpanded(Color fanColor, bool isHot, int fanSpeed) {
    return SizedBox(
      width: _expandedWidth,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('COOLING', style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                _spinningFan(fanColor, 18),
              ],
            ),
            const SizedBox(height: 12),
            _tempRow(LucideIcons.droplets, const Color(0xFF3B82F6), 'Water', widget.waterTempC, false),
            const SizedBox(height: 8),
            _tempRow(LucideIcons.home, const Color(0xFF8B5CF6), 'Housing', widget.ambientTempC, isHot),
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 8),
            if (!widget.isLive)
              const Text('No live data — check ESP32 connection',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11))
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    const Text('Fan Speed', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    if (_isUsingRealFanState) ...[
                      const SizedBox(width: 4),
                      Icon(LucideIcons.checkCircle2, size: 10, color: AppColors.success),
                    ],
                  ]),
                  Text('$fanSpeed%', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 6,
                  color: Colors.grey.shade100,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fanSpeed / 100,
                    child: Container(color: isHot ? const Color(0xFFEF4444) : AppColors.primary),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text('Tap to close · Drag to move', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade300, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _tempRow(IconData icon, Color iconColor, String label, double? value, bool highlightRed) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Icon(icon, color: iconColor, size: 13),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ]),
        Text(
          value != null ? '${value.toStringAsFixed(1)}°C' : '—',
          style: TextStyle(
            color: highlightRed ? const Color(0xFFEF4444) : AppColors.textPrimary,
            fontSize: 12, fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _spinningFan(Color color, double size) {
    if (_spinController == null) {
      return Icon(LucideIcons.fan, color: color, size: size);
    }
    return RotationTransition(
      // Counter-clockwise, matching the original's -360deg outputRange exactly.
      turns: Tween(begin: 0.0, end: -1.0).animate(_spinController!),
      child: Icon(LucideIcons.fan, color: color, size: size),
    );
  }

  void _snapToNearestEdge(FloatingWidgetPositionProvider provider, Size screenSize) {
    final widgetWidth = _expanded ? _expandedWidth : _widgetSize;
    final midpoint = screenSize.width / 2;
    final targetX = (provider.position.dx + widgetWidth / 2 < midpoint) ? 12.0 : screenSize.width - widgetWidth - 12;

    const minY = 60.0;
    final maxY = screenSize.height - 140;
    final targetY = provider.position.dy.clamp(minY, maxY);

    provider.updatePosition(Offset(targetX, targetY));
  }

  @override
  void dispose() {
    _opacityController.dispose();
    _scaleController.dispose();
    _spinController?.dispose();
    super.dispose();
  }
}
