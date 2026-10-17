import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import '../../widgets/motion.dart';

/// Startup sequence, in two deliberate phases:
///
///   1. DEFAULT SPLASH — a plain white screen, nothing on it. This is
///      the same white the native launch screen paints (Android's
///      `launch_background`, iOS's `LaunchScreen.storyboard`), so the
///      hand-off from the OS splash to Flutter's first frame is
///      seamless: no flash of a different colour, no visible seam.
///
///   2. BRANDED SPLASH — the CRX-Pulse logo scales and fades up out of
///      that same white, with the Lottie loader beneath it.
///
/// Then it fades into [next] (the auth gate).
class SplashScreen extends StatefulWidget {
  final Widget next;
  const SplashScreen({super.key, required this.next});

  /// Phase 1: how long the screen stays plain white.
  static const Duration whiteHold = Duration(milliseconds: 650);

  /// Phase 2: how long the branded splash is shown.
  static const Duration brandedHold = Duration(milliseconds: 2350);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// False during phase 1 (blank white), true once the logo appears.
  bool _branded = false;

  Timer? _brandTimer;
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();

    _brandTimer = Timer(SplashScreen.whiteHold, () {
      if (mounted) setState(() => _branded = true);
    });

    _exitTimer = Timer(
      SplashScreen.whiteHold + SplashScreen.brandedHold,
      _goNext,
    );
  }

  void _goNext() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: AppMotion.slow,
        reverseTransitionDuration: AppMotion.normal,
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(parent: anim, curve: AppMotion.enter);
          // Fade through, with the incoming screen settling in from a
          // hair larger — it reads as the splash receding rather than
          // one screen being swapped for another.
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 1.04, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _brandTimer?.cancel();
    _exitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The rest of the app sits under dark-green headers and so asks for
    // light status-bar icons (set in main()). On a white splash those
    // would be invisible, so this screen asks for dark ones and hands
    // the light setting back when it leaves.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        // Both phases sit on the same white, so phase 2 adds content
        // without the background ever changing.
        backgroundColor: Colors.white,
        body: Center(
          child: AnimatedOpacity(
            opacity: _branded ? 1 : 0,
            duration: AppMotion.slow,
            curve: AppMotion.enter,
            child: _branded ? const _BrandedSplash() : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _BrandedSplash extends StatelessWidget {
  const _BrandedSplash();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Scales up as it fades in, so the logo arrives rather than
        // simply being switched on.
        FadeSlideIn(
          duration: AppMotion.slow,
          from: Offset.zero,
          beginScale: 0.86,
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            child: Image(
              image: AssetImage('assets/images/Logo_Crx.png'),
              width: 200,
              fit: BoxFit.contain,
            ),
          ),
        ),
        SizedBox(height: 8),
        // Loader follows the logo in, a beat behind it.
        FadeSlideIn(
          delay: Duration(milliseconds: 220),
          child: _Loader(),
        ),
      ],
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      'assets/images/loader/loading.json',
      width: 120,
      height: 120,
      fit: BoxFit.contain,
      repeat: true,
    );
  }
}
