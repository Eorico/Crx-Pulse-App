import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

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
  bool _obscure = true;
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
      // Auth-state StreamBuilder in main.dart handles navigation
      // automatically once registration succeeds.
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
            const Text('Create account', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            const Text('Set up your pond monitoring account', style: TextStyle(color: AppColors.textMuted, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 28),

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

            const Text('Full name', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(controller: _nameController, decoration: const InputDecoration(hintText: 'Juan Dela Cruz', prefixIcon: Icon(LucideIcons.user, size: 18))),
            const SizedBox(height: 18),

            const Text('Email', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'you@example.com', prefixIcon: Icon(LucideIcons.mail, size: 18))),
            const SizedBox(height: 18),

            const Text('Password', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: 'At least 6 characters',
                prefixIcon: const Icon(LucideIcons.lock, size: 18),
                suffixIcon: IconButton(icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18), onPressed: () => setState(() => _obscure = !_obscure)),
              ),
            ),
            const SizedBox(height: 18),

            const Text('Confirm password', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(controller: _confirmController, obscureText: _obscure, decoration: const InputDecoration(hintText: 'Re-enter your password', prefixIcon: Icon(LucideIcons.lock, size: 18))),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _loading ? null : _onRegister,
                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Already have an account? ', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
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
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }
}
