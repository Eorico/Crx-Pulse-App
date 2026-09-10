import 'package:flutter/material.dart';

/// Spins the given image clockwise continuously while [spinning] is
/// true, stopping cleanly (not mid-frame-jump) when it becomes false.
class SpinningImage extends StatefulWidget {
  final String asset;
  final double size;
  final bool spinning;

  const SpinningImage({super.key, required this.asset, required this.size, required this.spinning});

  @override
  State<SpinningImage> createState() => _SpinningImageState();
}

class _SpinningImageState extends State<SpinningImage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1, milliseconds: 200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant SpinningImage old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.spinning && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Image.asset(widget.asset, width: widget.size, height: widget.size),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
