import 'package:flutter/material.dart';
import 'motion.dart';

/// Fades its child in once, on first mount — wrap any screen's body
/// (or any section of content) in this for a smoother, more deliberate
/// entrance instead of content snapping into view.
///
/// Now a thin wrapper over [FadeSlideIn] so every entrance in the app
/// shares one set of durations and curves (see [AppMotion]) and honours
/// the OS "reduce motion" setting. The constructor is unchanged, so
/// existing call sites keep working.
class FadeIn extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;

  const FadeIn({
    super.key,
    required this.child,
    this.duration = AppMotion.slow,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) => FadeSlideIn(
        duration: duration,
        delay: delay,
        from: const Offset(0, 0.03),
        child: child,
      );
}
