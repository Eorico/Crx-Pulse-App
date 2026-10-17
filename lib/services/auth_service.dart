import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Account system, now on Supabase Auth (was Firebase Auth). Supabase
/// handles password hashing, token refresh, and session persistence.
/// The display name is stored in the user's auth metadata
/// (user_metadata.display_name) — no separate profile table needed.
class AuthService {
  final SupabaseClient _sb = Supabase.instance.client;

  /// Kept so the register flow can briefly suppress the auth gate while
  /// it signs the brand-new account back out (so registration lands on
  /// Login, not straight into the app).
  static final ValueNotifier<bool> isProcessingRegistration = ValueNotifier(false);

  User? get currentUser => _sb.auth.currentUser;

  Future<void> signIn(String email, String password) async {
    await _sb.auth.signInWithPassword(email: email.trim(), password: password);
  }

  /// Registers the account (display name in metadata), then signs OUT so
  /// the user lands on Login to sign in fresh — matching the old flow.
  Future<void> register(String email, String password, String displayName) async {
    isProcessingRegistration.value = true;
    try {
      await _sb.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': displayName.trim()},
      );
      await _sb.auth.signOut();
    } finally {
      isProcessingRegistration.value = false;
    }
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _sb.auth.resetPasswordForEmail(email.trim());
  }

  /// OAuth sign-in. Requires the provider to be enabled in
  /// Supabase -> Authentication -> Providers, plus a deep-link redirect
  /// configured for the app. Email/password works with no extra setup.
  Future<void> signInWithGoogle() async {
    await _sb.auth.signInWithOAuth(OAuthProvider.google);
  }

  Future<void> signInWithFacebook() async {
    await _sb.auth.signInWithOAuth(OAuthProvider.facebook);
  }

  Future<void> signOut() => _sb.auth.signOut();

  /// The signed-in user's own profile fields, read from the auth user.
  Future<Map<String, dynamic>?> getMyAccountInfo() async {
    final u = _sb.auth.currentUser;
    if (u == null) return null;
    return {
      'displayName': (u.userMetadata?['display_name'] as String?) ?? '',
      'email': u.email ?? '',
      'createdAt': u.createdAt, // ISO-8601 string
    };
  }

  /// Plain-language messages from Supabase's AuthException.
  String friendlyError(Object e) {
    if (e is AuthException) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login') || m.contains('invalid credentials')) {
        return 'Incorrect email or password.';
      }
      if (m.contains('already registered') || m.contains('already been registered') || m.contains('already exists')) {
        return 'An account already exists with that email.';
      }
      if (m.contains('should be at least') || m.contains('password')) {
        return 'Please choose a stronger password (at least 6 characters).';
      }
      if (m.contains('not confirmed') || m.contains('confirm')) {
        return 'Please confirm your email first (check your inbox).';
      }
      if (m.contains('rate') || m.contains('too many')) {
        return 'Too many attempts. Please wait a moment and try again.';
      }
      return e.message;
    }
    return 'Something went wrong. Please try again.';
  }
}
