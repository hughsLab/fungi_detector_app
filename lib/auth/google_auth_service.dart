import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/app_secrets.dart';

class GoogleAuthService {
  GoogleAuthService({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
    String? clientId,
    String? serverClientId,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
        _clientId = clientId ?? (kIsWeb ? AppSecrets.googleWebClientId : null),
        _serverClientId = serverClientId ?? _defaultServerClientId();

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final String? _clientId;
  final String? _serverClientId;

  static Future<void>? _initializeFuture;

  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  Future<UserCredential?> signInWithGoogle() => signInWithGoogleDebug();

  Future<UserCredential?> signInWithGoogleDebug() async {
    debugPrint('GOOGLE_AUTH: signIn started');
    await _ensureInitialized();
    debugPrint('GOOGLE_AUTH: GoogleSignIn initialized');

    GoogleSignInAccount? googleUser;
    try {
      debugPrint('GOOGLE_AUTH: launching Google auth flow');
      googleUser = await _googleSignIn.authenticate();
      debugPrint('GOOGLE_AUTH: googleUser email=${googleUser.email}');
    } on GoogleSignInException catch (e, st) {
      debugPrint(
        'GOOGLE_AUTH: GoogleSignInException code=${e.code} message=${e.description}',
      );
      debugPrintStack(stackTrace: st, label: 'GOOGLE_AUTH');
      _logGoogleSignInHint(e);
      if (e.code == GoogleSignInExceptionCode.canceled) {
        debugPrint('GOOGLE_AUTH: user cancelled sign-in (googleUser == null)');
        return null;
      }
      if (e.code == GoogleSignInExceptionCode.interrupted ||
          e.code == GoogleSignInExceptionCode.uiUnavailable) {
        debugPrint('GOOGLE_AUTH_HINT: Google Sign-In UI unavailable');
      }
      rethrow;
    } on PlatformException catch (e, st) {
      debugPrint(
        'GOOGLE_AUTH: PlatformException code=${e.code} message=${e.message} details=${e.details}',
      );
      debugPrintStack(stackTrace: st, label: 'GOOGLE_AUTH');
      _logPlatformHint(e);
      rethrow;
    }

    final googleAuth = googleUser.authentication;
    final hasIdToken =
        googleAuth.idToken != null && googleAuth.idToken!.isNotEmpty;
    final accessToken = await _tryGetAccessToken(googleUser);
    debugPrint(
      'GOOGLE_AUTH: token presence idToken=$hasIdToken '
      'accessToken=${accessToken != null}',
    );

    if (!hasIdToken) {
      debugPrint('GOOGLE_AUTH: missing idToken, cannot continue');
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google ID token missing.',
      );
    }

    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: accessToken,
    );

    debugPrint('GOOGLE_AUTH: signing in with Firebase credential');
    try {
      final result = await _firebaseAuth.signInWithCredential(credential);
      debugPrint(
        'GOOGLE_AUTH: Firebase sign-in success uid=${result.user?.uid} '
        'email=${result.user?.email}',
      );
      return result;
    } on FirebaseAuthException catch (e, st) {
      debugPrint(
        'GOOGLE_AUTH: FirebaseAuthException code=${e.code} message=${e.message}',
      );
      debugPrintStack(stackTrace: st, label: 'GOOGLE_AUTH');
      _logFirebaseAuthHint(e);
      rethrow;
    } on PlatformException catch (e, st) {
      debugPrint(
        'GOOGLE_AUTH: PlatformException code=${e.code} message=${e.message} details=${e.details}',
      );
      debugPrintStack(stackTrace: st, label: 'GOOGLE_AUTH');
      _logPlatformHint(e);
      rethrow;
    } catch (e, st) {
      debugPrint('GOOGLE_AUTH: Unknown error: $e');
      debugPrintStack(stackTrace: st, label: 'GOOGLE_AUTH');
      rethrow;
    }
  }

  Future<void> signOut() async {
    debugPrint('GOOGLE_AUTH: signOut started');
    await _ensureInitialized();
    await Future.wait([
      _googleSignIn.signOut(),
      _firebaseAuth.signOut(),
    ]);
    debugPrint('GOOGLE_AUTH: signOut completed');
  }

  Future<void> _ensureInitialized() {
    final future = _initializeFuture;
    if (future != null) {
      return future;
    }
    if (kIsWeb && _clientId == null) {
      debugPrint(
        'GOOGLE_AUTH_HINT: Web requires GOOGLE_WEB_CLIENT_ID for Google Sign-In.',
      );
    }
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        _serverClientId == null) {
      debugPrint(
        'GOOGLE_AUTH_HINT: Android requires serverClientId for Google Sign-In. '
        'Use the Web client ID from Firebase/Google Cloud.',
      );
    }
    debugPrint(
      'GOOGLE_AUTH: initialize GoogleSignIn '
      'clientIdSet=${_clientId != null} serverClientIdSet=${_serverClientId != null}',
    );
    _initializeFuture = _googleSignIn.initialize(
      clientId: _clientId,
      serverClientId: _serverClientId,
    );
    return _initializeFuture!;
  }

  static String userMessageForError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'operation-not-allowed':
          return 'Google sign-in is disabled. Enable it in Firebase Console.';
        case 'account-exists-with-different-credential':
          return 'Account exists with different sign-in. Try another method.';
        case 'invalid-credential':
          return 'Invalid credential. Please try again.';
        default:
          return error.message ?? 'Sign-in failed. Please try again.';
      }
    }
    if (error is PlatformException) {
      if (_looksLikeDeveloperError(error.code, error.message, error.details)) {
        return 'Android config error. Check SHA-1/SHA-256 and package name.';
      }
      return error.message ?? 'Sign-in failed. Please try again.';
    }
    if (error is GoogleSignInException) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return 'Sign-in cancelled.';
      }
      if (error.code == GoogleSignInExceptionCode.clientConfigurationError) {
        return 'Google sign-in misconfigured. Check server client ID.';
      }
      return error.description ?? 'Google sign-in failed. Please try again.';
    }
    if (error is StateError) {
      return error.message ?? 'Missing configuration for Google sign-in.';
    }
    return 'Sign-in failed. Please try again.';
  }

  Future<String?> _tryGetAccessToken(GoogleSignInAccount googleUser) async {
    try {
      final authorization =
          await googleUser.authorizationClient.authorizationForScopes(
        const ['email'],
      );
      return authorization?.accessToken;
    } catch (e, st) {
      debugPrint('GOOGLE_AUTH: access token fetch failed: $e');
      debugPrintStack(stackTrace: st, label: 'GOOGLE_AUTH');
      return null;
    }
  }

  static void _logFirebaseAuthHint(FirebaseAuthException e) {
    final message = e.message ?? '';
    if (e.code == 'operation-not-allowed') {
      debugPrint(
        'GOOGLE_AUTH_HINT: Enable Google provider in Firebase Console.',
      );
    }
    if (_looksLikeDeveloperError(e.code, message, null)) {
      _logMissingShaHint();
    }
  }

  static void _logPlatformHint(PlatformException e) {
    if (_looksLikeDeveloperError(e.code, e.message, e.details)) {
      _logMissingShaHint();
    }
  }

  static void _logGoogleSignInHint(GoogleSignInException e) {
    if (e.code == GoogleSignInExceptionCode.clientConfigurationError) {
      debugPrint(
        'GOOGLE_AUTH_HINT: Missing/invalid serverClientId. '
        'Set it to the Web client ID in GoogleAuthService.',
      );
    }
  }

  static String? _defaultServerClientId() {
    if (kIsWeb) {
      return null;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AppSecrets.requireGoogleWebClientId();
    }
    return null;
  }

  static bool _looksLikeDeveloperError(
    String code,
    String? message,
    Object? details,
  ) {
    final haystack = [
      code,
      message ?? '',
      details?.toString() ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains('developer_error') ||
        haystack.contains('apiexception: 10') ||
        haystack.contains('12500') ||
        haystack.contains('sign_in_failed');
  }

  static void _logMissingShaHint() {
    debugPrint(
      'GOOGLE_AUTH_HINT: Likely missing SHA-1/SHA-256 or package name mismatch.',
    );
    debugPrint(
      'GOOGLE_AUTH_HINT: Run `cd android && .\\gradlew signingReport`, '
      'add SHA-1/SHA-256 in Firebase Console, then rebuild.',
    );
  }
}
