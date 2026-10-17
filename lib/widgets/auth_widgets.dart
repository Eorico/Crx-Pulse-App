import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../core/theme.dart';
import 'motion.dart';

/// Matches the original React Native auth screens' shared field
/// style (bg-white, rounded-2xl, subtle border+shadow) - used
/// identically across Login, Register, and Forgot Password rather
/// than each screen defining its own near-duplicate version.
///
/// The field now responds to focus: its border takes the brand green
/// and its shadow lifts, so which field you are typing in is obvious
/// without having to look for the caret.
class AuthTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;

    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.enter,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focused ? AppColors.primaryLight : const Color(0xFFE5E7EB),
          width: focused ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: focused
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: focused ? 12 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        obscureText: widget.obscure,
        keyboardType: widget.keyboardType,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: Color(0xFF999999)),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          suffixIcon: widget.suffix,
        ),
      ),
    );
  }
}

class AuthFieldLabel extends StatelessWidget {
  final String text;
  const AuthFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}

class PrimaryAuthButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  const PrimaryAuthButton({super.key, required this.label, required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          shadowColor: AppColors.primary.withValues(alpha: 0.3),
          animationDuration: AppMotion.fast,
        ),
        // Label and spinner cross-fade, and the button keeps its height
        // through the swap so nothing below it shifts.
        child: SwapIn(
          swapKey: loading,
          duration: AppMotion.fast,
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5)),
        ),
      ),
    );
  }
}

class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Row(children: [
        Expanded(child: Divider(color: Color(0xFFE5E7EB))),
        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OR', style: TextStyle(color: Colors.grey, fontSize: 12))),
        Expanded(child: Divider(color: Color(0xFFE5E7EB))),
      ]),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  final String message;
  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.red.shade200)),
      child: Row(children: [
        Icon(LucideIcons.alertCircle, color: Colors.red.shade600, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
      ]),
    );
  }
}

/// Social sign-in buttons - positioned at the bottom of both Login
/// and Register. "Continue with an existing Gmail account" isn't a
/// separate button here: a Gmail account IS a Google account, so
/// the Google button already covers that case - a second, redundant
/// button would just confuse people about which one to tap.
class SocialSignInButtons extends StatelessWidget {
  final VoidCallback onGooglePressed;
  final VoidCallback onFacebookPressed;
  final bool loading;
  final String heading;

  const SocialSignInButtons({
    super.key,
    required this.onGooglePressed,
    required this.onFacebookPressed,
    this.loading = false,
    this.heading = 'Continue with',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(heading, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _SocialButton(
                label: 'Google',
                icon: FontAwesomeIcons.google,
                onPressed: loading ? null : onGooglePressed,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SocialButton(
                label: 'Facebook',
                icon: FontAwesomeIcons.facebook,
                iconColor: const Color(0xFF1877F2),
                onPressed: loading ? null : onFacebookPressed,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final FaIconData icon;
  final Color? iconColor;
  final VoidCallback? onPressed;
  const _SocialButton({required this.label, required this.icon, this.iconColor, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFE5E7EB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: Colors.white,
          animationDuration: AppMotion.fast,
        ),
        icon: FaIcon(icon, size: 18, color: iconColor ?? const Color(0xFF4B5563)),
        label: Text(label, style: const TextStyle(color: Color(0xFF374151), fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}
