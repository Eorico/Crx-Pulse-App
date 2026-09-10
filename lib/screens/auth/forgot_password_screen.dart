import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

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
    if (_emailController.text.trim().isEmpty) return;
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
      appBar: AppBar(backgroundColor: AppColors.background, elevation: 0, iconTheme: const IconThemeData(color: AppColors.textPrimary)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: const Icon(LucideIcons.mail, color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 24),
            const Text('Reset password', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            const Text("Enter your email and we'll send you a link to reset your password.", style: TextStyle(color: AppColors.textMuted, fontSize: 14, fontWeight: FontWeight.w500, height: 1.4)),
            const SizedBox(height: 28),

            if (_sent)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.success.withValues(alpha: 0.3))),
                child: Row(children: [
                  const Icon(LucideIcons.checkCircle, color: AppColors.success, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Check your inbox at ${_emailController.text.trim()} for the reset link.', style: const TextStyle(color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w600))),
                ]),
              )
            else ...[
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.red.shade200)),
                  child: Row(children: [
                    Icon(LucideIcons.alertCircle, color: Colors.red.shade600, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                  ]),
                ),
              ],
              const Text('Email', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'you@example.com', prefixIcon: Icon(LucideIcons.mail, size: 18))),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _loading ? null : _onSend,
                  style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Send Reset Link', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Remember your password? ', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text('Sign in', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
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
