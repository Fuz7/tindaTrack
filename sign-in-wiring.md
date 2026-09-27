# Wiring up `onSignIn`

Notes on why `SignInScreen.onSignIn` is currently `null`, what "app shell" means,
and the four ways to fix it.

---

## 1. What "app shell" means

Nothing official — it's the informal name for the widget near the top of the tree
that owns app-wide concerns: theme, routing, and which screen is currently
showing. In this project that's `TindaTrackApp` / `_TindaTrackAppState` in
`lib/main.dart`.

```
runApp()
└── TindaTrackApp            ← the "shell"
    └── MaterialApp          theme, title, navigation
        └── home:
            ├── IntroScreen      (if !seenIntro)
            └── SignInScreen     (otherwise)
```

The shell already does shell-type work: it reads `SharedPreferences`, holds
`_showIntro`, and swaps screens when the intro finishes. Screens below it are
meant to be dumb — they draw pixels and report events upward.

That's the pattern `IntroScreen` already follows:

```dart
IntroScreen(onDone: _completeIntro)
```

`IntroScreen` doesn't know what "done" means. It just calls the callback, and the
shell decides that means "save the flag and show sign-in".

## 2. Why `onSignIn` is null

`lib/main.dart:54`

```dart
: const SignInScreen(),     // no onSignIn argument passed
```

`onSignIn` is an *optional named* parameter with no default, so omitting it makes
it `null`. Then the guard in `_handleSignIn` returns immediately:

```dart
final callback = widget.onSignIn;
if (callback == null || _busy) return;
```

The button renders as enabled and ripples on tap, but nothing happens.

---

## Option A — pass the callback down from the shell

Keep the screen dumb. Auth logic lives in `main.dart`.

**`lib/main.dart`**

```dart
Future<void> _handleGoogleSignIn() async {
  // ... Firebase call here (see section 5)
}

@override
Widget build(BuildContext context) {
  return MaterialApp(
    // ...
    home: _showIntro
        ? IntroScreen(onDone: _completeIntro)
        : SignInScreen(onSignIn: _handleGoogleSignIn),   // `const` must go
  );
}
```

`const` has to be dropped because `_handleGoogleSignIn` is a runtime value.

- ✅ Consistent with how `IntroScreen` works
- ✅ `SignInScreen` stays trivial to test — pass a fake callback
- ❌ Auth code piles up in `main.dart` as the app grows

## Option B — make the callback required

Same as A, but the compiler catches a missing callback instead of you finding out
by tapping a dead button.

**`lib/screens/sign_in_screen.dart`**

```dart
const SignInScreen({super.key, required this.onSignIn});

final Future<void> Function() onSignIn;   // note: no `?`
```

The null guard in `_handleSignIn` then simplifies to:

```dart
Future<void> _handleSignIn() async {
  if (_busy) return;
  setState(() => _busy = true);
  try {
    await widget.onSignIn();
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}
```

- ✅ Bug becomes impossible — this exact problem can't recur
- ❌ Slightly less flexible (can't render the screen with a no-op button)

**This is the smallest change that actually prevents the bug you hit.**

## Option C — do the sign-in inside the screen

Delete the parameter entirely and call Firebase from `_handleSignIn`.

```dart
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  // no onSignIn at all
}

// in _SignInScreenState:
Future<void> _handleSignIn() async {
  if (_busy) return;
  setState(() => _busy = true);
  try {
    await _signInWithGoogle();     // section 5
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}
```

- ✅ Fewest moving parts; `main.dart` untouched
- ❌ Screen now owns UI *and* auth — harder to test, harder to reuse
- ❌ You still need the shell to react to a successful sign-in and swap screens

## Option D — auth service + `authStateChanges` (recommended)

The Firebase-native approach: nobody passes callbacks around, and the shell reacts
to auth state instead of being told about it.

**`lib/services/auth_service.dart`** (new file)

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static Stream<User?> get authState => FirebaseAuth.instance.authStateChanges();

  static Future<void> signInWithGoogle() async {
    // ... section 5
  }

  static Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();
  }
}
```

**`lib/main.dart`**

```dart
home: _showIntro
    ? IntroScreen(onDone: _completeIntro)
    : StreamBuilder<User?>(
        stream: AuthService.authState,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snapshot.hasData
              ? const DashboardScreen()
              : SignInScreen(onSignIn: AuthService.signInWithGoogle);
        },
      ),
```

Why this fits TindaTrack specifically:

- Multiple devices share one store, so **every** device needs to know who's signed
  in, not just the sign-in screen
- `authStateChanges` fires on app restart too, so returning users skip sign-in
  automatically — no manual token juggling
- Sign-out from anywhere in the app routes back to `SignInScreen` for free
- Firestore security rules key off `request.auth.uid`, so you need the `User`
  object available app-wide anyway

- ✅ Scales to the rest of the app; handles restart and sign-out
- ❌ More upfront structure than the app strictly needs today

---

## 5. The actual Google sign-in call

`pubspec.yaml` already has `google_sign_in: ^7.2.0`. **Version 7 changed the API
substantially** — most tutorials online show the v6 style (`GoogleSignIn()`,
`signIn()`, `accessToken`) which will not compile here.

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

Future<void> signInWithGoogle() async {
  // Must be called exactly once before authenticate(). Safe to do at app
  // startup in main() instead of here.
  await GoogleSignIn.instance.initialize(
    serverClientId: '<WEB client ID from Firebase console>',
  );

  final account = await GoogleSignIn.instance.authenticate();
  final idToken = account.authentication.idToken;

  if (idToken == null) {
    throw StateError('Google returned no ID token');
  }

  await FirebaseAuth.instance.signInWithCredential(
    GoogleAuthProvider.credential(idToken: idToken),
  );
}
```

Notes on the v7 API:

| v6 (old tutorials) | v7 (what you have) |
|---|---|
| `GoogleSignIn()` constructor | `GoogleSignIn.instance` singleton |
| `signIn()` | `authenticate()` |
| returns `null` on cancel | throws `GoogleSignInException` |
| `auth.accessToken` + `auth.idToken` | `auth.idToken` only |
| no init step | `initialize()` required first |

Cancellation is now an exception, so handle it:

```dart
try {
  await signInWithGoogle();
} on GoogleSignInException catch (e) {
  if (e.code == GoogleSignInExceptionCode.canceled) return;  // user backed out
  rethrow;
}
```

`attemptLightweightAuthentication()` is the silent variant — useful on startup to
restore a previous session without showing UI.

## 6. Android setup (required, easy to forget)

Google sign-in fails at runtime with a vague `ApiException: 10` if these aren't
done:

1. Get the debug SHA-1:
   ```bash
   cd android && ./gradlew signingReport
   ```
2. Firebase Console → Project Settings → Your Android app → **Add fingerprint** →
   paste the SHA-1
3. Re-download `google-services.json` into `android/app/`
4. Firebase Console → Authentication → Sign-in method → enable **Google**
5. The `serverClientId` above is the **Web** client ID (type 3) from
   `google-services.json` or the Google Cloud credentials page — not the Android
   one

Release builds need the release keystore's SHA-1 added too.

---

## Recommendation

Ship **Option B** now if you just want the button working today — it's a two-line
change and makes the bug unrepeatable.

Move to **Option D** before building the dashboard. Once more than one screen
needs to know who's signed in, passing callbacks down stops scaling, and you'll
want `authStateChanges` anyway for the multi-device story.

A and D compose fine: D still passes `onSignIn` into the screen, it just sources
it from a service instead of from `main.dart`.
