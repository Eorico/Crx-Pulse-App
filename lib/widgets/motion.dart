import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// CRX-Pulse motion system.
///
/// One place for every duration, curve and reusable animation in the
/// app, so motion reads as a single deliberate language instead of each
/// screen inventing its own timings. Everything here respects
/// [MediaQuery.disableAnimations] (the OS "reduce motion" setting) by
/// collapsing to an instant, static result rather than a jerky partial
/// animation — an app on a tank wall should still be fully usable for
/// someone who has motion effects turned off.
class AppMotion {
  AppMotion._();

  /// Tap feedback, toggles — fast enough to feel like a direct response.
  static const fast = Duration(milliseconds: 160);

  /// The default: card entrances, value changes, colour shifts.
  static const normal = Duration(milliseconds: 320);

  /// Screen-level entrances and larger reveals.
  static const slow = Duration(milliseconds: 520);

  /// Gap between consecutive items in a staggered list.
  static const stagger = Duration(milliseconds: 55);

  /// Decelerating — the default for anything entering the screen.
  static const enter = Curves.easeOutCubic;

  /// Accelerating — for anything leaving.
  static const exit = Curves.easeInCubic;

  /// A touch of overshoot. Used sparingly: selected tabs, success states.
  static const spring = Curves.easeOutBack;

  /// Smooth both ends — continuous values (gauges, progress, numbers).
  static const smooth = Curves.easeInOutCubic;

  /// True when the OS asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Stagger delay for item [index], capped so a long list does not
  /// leave the last rows waiting seconds to appear.
  static Duration delayFor(int index, {int max = 10}) =>
      stagger * index.clamp(0, max);
}

/// Fades and slides its child in once, on first mount.
///
/// The workhorse entrance. [delay] drives the stagger; [from] picks the
/// direction the child travels in from (defaults to slightly below).
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Offset from;
  final double beginScale;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = AppMotion.normal,
    this.delay = Duration.zero,
    this.from = const Offset(0, 0.06),
    this.beginScale = 1.0,
  });

  /// Convenience for building a staggered list: wraps each child with an
  /// increasing delay.
  static List<Widget> stagger(
    List<Widget> children, {
    Duration duration = AppMotion.normal,
    Duration initialDelay = Duration.zero,
    Offset from = const Offset(0, 0.06),
  }) {
    return [
      for (int i = 0; i < children.length; i++)
        FadeSlideIn(
          duration: duration,
          delay: initialDelay + AppMotion.delayFor(i),
          from: from,
          child: children[i],
        ),
    ];
  }

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _c, curve: AppMotion.enter);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (AppMotion.reduced(context)) {
      _c.value = 1.0;
      return;
    }
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          opacity: t,
          child: FractionalTranslation(
            translation: Offset(
              widget.from.dx * (1 - t),
              widget.from.dy * (1 - t),
            ),
            child: widget.beginScale == 1.0
                ? child
                : Transform.scale(
                    scale: widget.beginScale + (1 - widget.beginScale) * t,
                    child: child,
                  ),
          ),
        );
      },
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}

/// Wraps any tappable thing so it visibly depresses under the finger.
///
/// This is the piece that makes the clay surfaces feel physical: press
/// and the card sinks and dims slightly, release and it springs back.
/// Use it instead of a bare [GestureDetector] on cards and tiles.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How far down it scales while held.
  final double pressedScale;

  /// Fire a selection tick on press. On by default for taps that
  /// change something; turn it off for purely navigational taps that
  /// already have their own feedback.
  final bool haptic;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.haptic = true,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: AppMotion.fast);

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _down() {
    if (!_enabled) return;
    _c.forward();
  }

  void _up() {
    if (!_enabled) return;
    _c.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      onTap: _enabled
          ? () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap?.call();
            }
          : null,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!.call();
            },
      child: reduced
          ? widget.child
          : AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                final t = _c.value;
                return Transform.scale(
                  scale: 1 - (1 - widget.pressedScale) * t,
                  child: Opacity(opacity: 1 - 0.12 * t, child: child),
                );
              },
              child: widget.child,
            ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}

/// A number that counts to its new value instead of snapping.
///
/// Sensor readings arrive every ten seconds; animating between them
/// makes a change read as movement rather than a flicker, and makes it
/// obvious at a glance which direction a value went.
class AnimatedNumber extends StatelessWidget {
  final double value;
  final int decimals;
  final String suffix;
  final String prefix;
  final TextStyle? style;
  final Duration duration;
  final TextAlign? textAlign;

  const AnimatedNumber({
    super.key,
    required this.value,
    this.decimals = 1,
    this.suffix = '',
    this.prefix = '',
    this.style,
    this.duration = AppMotion.slow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) {
      return Text('$prefix${value.toStringAsFixed(decimals)}$suffix',
          style: style, textAlign: textAlign);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: value, end: value),
      duration: duration,
      curve: AppMotion.smooth,
      builder: (context, v, _) => Text(
        '$prefix${v.toStringAsFixed(decimals)}$suffix',
        style: style,
        textAlign: textAlign,
      ),
    );
  }
}

/// A soft halo that breathes outward, for "this is live" indicators.
///
/// Deliberately slow and low-contrast: it should register in peripheral
/// vision as a heartbeat, not compete with the reading it sits next to.
class PulseHalo extends StatefulWidget {
  final Widget child;
  final Color color;
  final bool active;
  final double maxRadius;

  const PulseHalo({
    super.key,
    required this.child,
    required this.color,
    this.active = true,
    this.maxRadius = 14,
  });

  @override
  State<PulseHalo> createState() => _PulseHaloState();
}

class _PulseHaloState extends State<PulseHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant PulseHalo old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || AppMotion.reduced(context)) return widget.child;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.30 * (1 - t)),
                blurRadius: widget.maxRadius * (0.4 + t),
                spreadRadius: widget.maxRadius * 0.25 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}

/// Very slow scale breathing. Used on the dashboard mascot so the hero
/// card is never completely still, without drawing the eye.
class Breathing extends StatefulWidget {
  final Widget child;
  final bool active;
  final double amount;

  const Breathing({
    super.key,
    required this.child,
    this.active = true,
    this.amount = 0.035,
  });

  @override
  State<Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant Breathing old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || AppMotion.reduced(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.scale(
        scale: 1 + widget.amount * Curves.easeInOut.transform(_c.value),
        child: child,
      ),
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}

/// Drives a 0→1 progress value once on mount — for charts that draw
/// themselves in, gauges that sweep up to their reading, bars that grow.
class DrawIn extends StatelessWidget {
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final Widget Function(BuildContext context, double t) builder;

  const DrawIn({
    super.key,
    required this.builder,
    this.duration = const Duration(milliseconds: 900),
    this.delay = Duration.zero,
    this.curve = AppMotion.smooth,
  });

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return builder(context, 1.0);
    return _DrawInRunner(
      duration: duration,
      delay: delay,
      curve: curve,
      builder: builder,
    );
  }
}

class _DrawInRunner extends StatefulWidget {
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final Widget Function(BuildContext context, double t) builder;

  const _DrawInRunner({
    required this.duration,
    required this.delay,
    required this.curve,
    required this.builder,
  });

  @override
  State<_DrawInRunner> createState() => _DrawInRunnerState();
}

class _DrawInRunnerState extends State<_DrawInRunner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _c, curve: widget.curve);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _curve,
        builder: (context, _) => widget.builder(context, _curve.value),
      );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}

/// Cross-fades between two children by value identity, scaling the
/// incoming one up slightly. Used for anything that swaps in place: a
/// status word, a connection icon, a reading replacing "Not Connected".
class SwapIn extends StatelessWidget {
  final Widget child;
  final Object? swapKey;
  final Duration duration;

  const SwapIn({
    super.key,
    required this.child,
    this.swapKey,
    this.duration = AppMotion.normal,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.88, end: 1.0)
              .animate(CurvedAnimation(parent: anim, curve: AppMotion.enter)),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.center,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey(swapKey ?? child.hashCode), child: child),
    );
  }
}
