import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/motion.dart';

/// Pixel-matched to the original React Native forget-password.screen.tsx:
/// green header with back button, Forgot.png artwork, info box with
/// Mail icon, green success banner, "Remember your password?" link.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _auth = AuthService();
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  Future<void> _onSend() async {
    if (_emailController.text.trim().isEmpty || _sent) return;
    setState(() { _loading = true; _error = null; });
    try {
      await _auth.sendPasswordResetEmail(_emailController.text);
      setState(() => _sent = true);
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
                        Image.asset('assets/images/Forgot.png', width: double.infinity, height: 180, fit: BoxFit.contain),
                        const SizedBox(height: 16),
                        const Text('Reset Password', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text("We'll send a reset link to your email", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFC8D8C8), fontSize: 14)),
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
                    // INFO BOX
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(LucideIcons.mail, color: AppColors.primary, size: 20),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Enter your registered email and we'll send you a link to reset your password.",
                              style: TextStyle(color: AppColors.primary, fontSize: 14, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),

                    AnimatedSize(
                      duration: AppMotion.normal,
                      curve: AppMotion.smooth,
                      alignment: Alignment.topCenter,
                      child: _error != null
                          ? AuthErrorBanner(message: _error!)
                          : const SizedBox(width: double.infinity),
                    ),

                    const AuthFieldLabel('Email Address'),
                    AuthTextField(controller: _emailController, hint: 'your@email.com', keyboardType: TextInputType.emailAddress),

                    // SUCCESS BANNER — slides open under the field.
                    if (_sent) ...[
                      FadeSlideIn(
                        from: const Offset(0, 0.2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          margin: const EdgeInsets.only(top: 16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            border: Border.all(color: Colors.green.shade300),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('✓',
                                  style: TextStyle(color: Colors.green.shade600, fontSize: 20)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Reset link sent!',
                                        style: TextStyle(
                                            color: Colors.green.shade700,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text('Please check your inbox and spam folder.',
                                        style: TextStyle(
                                            color: Colors.green.shade600, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    PrimaryAuthButton(
                      label: _sent ? 'Link Sent ✓' : 'Send Reset Link',
                      loading: _loading,
                      onPressed: _onSend,
                    ),

                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Center(
                        child: PressableScale(
                          pressedScale: 0.94,
                          onTap: () => Navigator.pop(context),
                          child: RichText(
                            text: const TextSpan(
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                              children: [
                                TextSpan(text: 'Remember your password? '),
                                TextSpan(text: 'Sign In', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
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
    super.dispose();
  }
}
