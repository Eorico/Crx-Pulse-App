import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Thin wrapper around FirebaseAuth - the actual account system now,
/// replacing the old custom JWT backend entirely. Firebase handles
/// password hashing, token refresh, and session persistence on its
/// own; this class just exposes the operations the UI needs.
///
/// Firestore structure this writes to:
///   users/{uid}/account-information/profile
/// Every document this class ever touches is scoped under the
/// CURRENTLY authenticated user's own UID - there is no code path
/// here that can read or write another user's data, which is also
/// enforced server-side by the Firestore security rules regardless.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<UserCredential> register(String email, String password, String displayName) async {
    final credential = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    final user = credential.user;
    if (user == null) return credential;

    await user.updateDisplayName(displayName.trim());

    // Per the required Firestore structure: registration details go
    // under this user's OWN document, in a fixed-name "profile" doc
    // within account-information - never anywhere shared, never
    // keyed by name (the UID is the only identifier used).
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('account-information')
        .doc('profile')
        .set({
      'displayName': displayName.trim(),
      'email': email.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return credential;
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() => _auth.signOut();

  /// Reads the CURRENTLY signed-in user's own account-information
  /// document - never accepts a UID parameter, so it's structurally
  /// impossible to call this for anyone but yourself.
  Future<Map<String, dynamic>?> getMyAccountInfo() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('account-information')
        .doc('profile')
        .get();
    return doc.data();
  }

  /// Translates Firebase's error codes into plain-language messages -
  /// the raw codes (e.g. "wrong-password", "user-not-found") aren't
  /// something to show someone directly.
  String friendlyError(Object e) {
    if (e is! FirebaseAuthException) return 'Something went wrong. Please try again.';
    switch (e.code) {
      case 'invalid-email':
        return 'That email address doesn\'t look right.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found with that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists with that email.';
      case 'weak-password':
        return 'Please choose a stronger password (at least 6 characters).';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection - check your mobile data or WiFi.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }
}
