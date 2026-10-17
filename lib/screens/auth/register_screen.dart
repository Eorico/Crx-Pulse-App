import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/motion.dart';

/// Pixel-matched to the original React Native register.screen.tsx:
/// green header with back button, Register.png artwork, per-field
/// eye toggles, OR divider, Sign In link.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _auth = AuthService();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  Future<void> _onRegister() async {
    if (_nameController.text.trim().isEmpty || _emailController.text.trim().isEmpty || _passwordController.text.isEmpty) return;
    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = "Passwords don't match.");
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await _auth.register(_emailController.text, _passwordController.text, _nameController.text);
      // register() already signs back out internally - _AuthGate's
      // stream will land on a fresh LoginScreen automatically once
      // this pop completes, but pop explicitly too so this screen
      // itself doesn't linger stacked on top in the meantime.
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created! Please sign in.')),
        );
      }
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
      // Unlike email/password registration, social sign-in doesn't
      // get signed back out - there's no separate "confirm your
      // email" step needed, so landing straight in the app here is
      // the correct, expected behavior for this path.
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
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
                    ),
                    child: Column(
                      children: FadeSlideIn.stagger([
                        const SizedBox(height: 30),
                        Image.asset('assets/images/Register.png', width: double.infinity, height: 180, fit: BoxFit.contain),
                        const SizedBox(height: 16),
                        const Text('Create Account', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text('Join CRX-Pulse and start monitoring', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFC8D8C8), fontSize: 14)),
                      ]),
                    ),
                  ),
                  Positioned(
                    left: 20, top: 16,
                    child: SafeArea(
                      bottom: false,
                      child: Container(
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: IconButton(
                          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white, size: 22),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ── FORM ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: FadeSlideIn.stagger([
                    // Expands/collapses rather than jolting the form.
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

                    const AuthFieldLabel('Full Name'),
                    AuthTextField(controller: _nameController, hint: 'Juan Dela Cruz'),
                    const SizedBox(height: 16),

                    const AuthFieldLabel('Email Address'),
                    AuthTextField(controller: _emailController, hint: 'your@email.com', keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 16),

                    const AuthFieldLabel('Password'),
                    AuthTextField(
                      controller: _passwordController,
                      hint: 'At least 6 characters',
                      obscure: _obscurePassword,
                      suffix: IconButton(
                        icon: Icon(_obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff, color: const Color(0xFF999999), size: 18),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const AuthFieldLabel('Confirm Password'),
                    AuthTextField(
                      controller: _confirmController,
                      hint: 'Re-enter your password',
                      obscure: _obscureConfirm,
                      suffix: IconButton(
                        icon: Icon(_obscureConfirm ? LucideIcons.eye : LucideIcons.eyeOff, color: const Color(0xFF999999), size: 18),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),

                    const SizedBox(height: 24),
                    PrimaryAuthButton(label: 'Create Account', loading: _loading, onPressed: _onRegister),

                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Already have an account? ', style: TextStyle(color: Colors.grey, fontSize: 14)),
                        PressableScale(
                          pressedScale: 0.92,
                          onTap: () => Navigator.pop(context),
                          child: const Text('Sign In', style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.bold)),
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
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }
}
