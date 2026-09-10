import 'package:flutter/material.dart';

/// Fades its child in once, on first mount - wrap any screen's body
/// (or any section of content) in this for a smoother, more
/// deliberate entrance instead of content just snapping into view.
class FadeIn extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const FadeIn({super.key, required this.child, this.duration = const Duration(milliseconds: 450)});

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, 0.03), end: Offset.zero)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
