import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Everything auth-related lives here so no screen has to know about Firebase.
///
/// The app shell listens to [authState] and swaps screens; screens only ever
/// call [signInWithGoogle] / [signOut].
class AuthService {
  AuthService._();

  /// The **Web** client (type 3) from `android/app/google-services.json`.
  /// Not the Android client — using the Android one yields `ApiException: 10`.
  static const _serverClientId =
      '930423513347-8mls8p0173r1bftabgivt2r5j475kde2.apps.googleusercontent.com';

  /// Fires on sign-in, sign-out, and once on startup with the restored user
  /// (or null). This is what lets a returning user skip the sign-in screen.
  static final Stream<User?> authState = FirebaseAuth.instance
      .authStateChanges();

  static User? get currentUser => FirebaseAuth.instance.currentUser;

  /// Must run exactly once before [signInWithGoogle]. Called from `main()`.
  static Future<void> initialize() =>
      GoogleSignIn.instance.initialize(serverClientId: _serverClientId);

  /// Opens the Google account picker and signs the resulting user into
  /// Firebase. Success is not reported back to the caller — the shell picks it
  /// up from [authState].
  ///
  /// Backing out of the picker is a normal outcome, not a failure, so the
  /// v7 `canceled` exception is swallowed here. Anything else is rethrown for
  /// the caller to surface.
  static Future<void> signInWithGoogle() async {
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google returned no ID token');
    }

    await FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  /// Signs out of Google too, so the next sign-in shows the account picker
  /// instead of silently reusing the last account.
  static Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();
  }
}
