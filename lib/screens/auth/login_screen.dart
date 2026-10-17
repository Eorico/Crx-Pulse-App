import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/motion.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

/// Pixel-matched to the original React Native login.screen.tsx:
/// green rounded-bottom header with the CRX-PULSE badge, the real
/// Login.png artwork, cream form area below, OR divider, Sign Up
/// link - same layout, same colors, same copy.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  Future<void> _onSignIn() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await _auth.signIn(_emailController.text, _passwordController.text);
    } catch (e) {
      setState(() => _error = _auth.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onGoogleSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _auth.signInWithGoogle();
    } catch (e) {
      setState(() => _error = _auth.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onFacebookSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _auth.signInWithFacebook();
    } catch (e) {
      setState(() => _error = _auth.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── HEADER ──
              Container(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
                ),
                // Badge, artwork, then the two lines of copy, each a
                // beat behind the last.
                child: Column(
                  children: FadeSlideIn.stagger([
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                      child: const Text('CRX-PULSE', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 2)),
                    ),
                    const SizedBox(height: 24),
                    Image.asset('assets/images/Login.png', width: double.infinity, height: 200, fit: BoxFit.contain),
                    const SizedBox(height: 16),
                    const Text('Welcome Back', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('Sign in to monitor your crayfish system', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFC8D8C8), fontSize: 14)),
                  ]),
                ),
              ),

              // ── FORM ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: FadeSlideIn.stagger([
                    // The error banner expands into place and collapses
                    // away, so it never jolts the form.
                    AnimatedSize(
                      duration: AppMotion.normal,
                      curve: AppMotion.smooth,
                      alignment: Alignment.topCenter,
                      child: _error != null
                          ? AuthErrorBanner(message: _error!)
                          : const SizedBox(width: double.infinity),
                    ),

                    // Social sign-in first, above the email form.
                    SocialSignInButtons(
                      loading: _loading,
                      onGooglePressed: _onGoogleSignIn,
                      onFacebookPressed: _onFacebookSignIn,
                    ),
                    const AuthOrDivider(),

                    const AuthFieldLabel('Email Address'),
                    AuthTextField(controller: _emailController, hint: 'your@email.com', keyboardType: TextInputType.emailAddress),

                    const SizedBox(height: 20),
                    const AuthFieldLabel('Password'),
                    AuthTextField(
                      controller: _passwordController,
                      hint: 'Enter your password',
                      obscure: _obscure,
                      suffix: IconButton(
                        icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, color: const Color(0xFF999999), size: 18),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: PressableScale(
                          pressedScale: 0.92,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                          child: const Text('Forgot Password?', style: TextStyle(color: AppColors.accent, fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    PrimaryAuthButton(label: 'Sign In', loading: _loading, onPressed: _onSignIn),

                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account? ", style: TextStyle(color: Colors.grey, fontSize: 14)),
                        PressableScale(
                          pressedScale: 0.92,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                          child: const Text('Sign Up', style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
