import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class EmailAuthService {
  EmailAuthService({FirebaseAuth? firebaseAuth})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    debugPrint('EMAIL_AUTH: signIn started');
    try {
      final result = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      debugPrint(
        'EMAIL_AUTH: signIn success uid=${result.user?.uid} '
        'email=${result.user?.email}',
      );
      return result;
    } on FirebaseAuthException catch (e, st) {
      debugPrint(
        'EMAIL_AUTH: FirebaseAuthException code=${e.code} message=${e.message}',
      );
      debugPrintStack(stackTrace: st, label: 'EMAIL_AUTH');
      rethrow;
    } on PlatformException catch (e, st) {
      debugPrint(
        'EMAIL_AUTH: PlatformException code=${e.code} message=${e.message} '
        'details=${e.details}',
      );
      debugPrintStack(stackTrace: st, label: 'EMAIL_AUTH');
      rethrow;
    } catch (e, st) {
      debugPrint('EMAIL_AUTH: Unknown error: $e');
      debugPrintStack(stackTrace: st, label: 'EMAIL_AUTH');
      rethrow;
    }
  }

  Future<UserCredential> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    debugPrint('EMAIL_AUTH: signUp started');
    try {
      final result = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      debugPrint(
        'EMAIL_AUTH: signUp success uid=${result.user?.uid} '
        'email=${result.user?.email}',
      );
      return result;
    } on FirebaseAuthException catch (e, st) {
      debugPrint(
        'EMAIL_AUTH: FirebaseAuthException code=${e.code} message=${e.message}',
      );
      debugPrintStack(stackTrace: st, label: 'EMAIL_AUTH');
      rethrow;
    } on PlatformException catch (e, st) {
      debugPrint(
        'EMAIL_AUTH: PlatformException code=${e.code} message=${e.message} '
        'details=${e.details}',
      );
      debugPrintStack(stackTrace: st, label: 'EMAIL_AUTH');
      rethrow;
    } catch (e, st) {
      debugPrint('EMAIL_AUTH: Unknown error: $e');
      debugPrintStack(stackTrace: st, label: 'EMAIL_AUTH');
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    debugPrint('EMAIL_AUTH: sendPasswordResetEmail started');
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
      debugPrint('EMAIL_AUTH: sendPasswordResetEmail success');
    } on FirebaseAuthException catch (e, st) {
      debugPrint(
        'EMAIL_AUTH: FirebaseAuthException code=${e.code} message=${e.message}',
      );
      debugPrintStack(stackTrace: st, label: 'EMAIL_AUTH');
      rethrow;
    } on PlatformException catch (e, st) {
      debugPrint(
        'EMAIL_AUTH: PlatformException code=${e.code} message=${e.message} '
        'details=${e.details}',
      );
      debugPrintStack(stackTrace: st, label: 'EMAIL_AUTH');
      rethrow;
    } catch (e, st) {
      debugPrint('EMAIL_AUTH: Unknown error: $e');
      debugPrintStack(stackTrace: st, label: 'EMAIL_AUTH');
      rethrow;
    }
  }

  Future<void> sendEmailVerification({User? user}) async {
    final targetUser = user ?? _firebaseAuth.currentUser;
    if (targetUser == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in user.',
      );
    }
    debugPrint('EMAIL_AUTH: sendEmailVerification started');
    try {
      await targetUser.sendEmailVerification();
      debugPrint('EMAIL_AUTH: sendEmailVerification success');
    } on FirebaseAuthException catch (e, st) {
      debugPrint(
        'EMAIL_AUTH: FirebaseAuthException code=${e.code} message=${e.message}',
      );
      debugPrintStack(stackTrace: st, label: 'EMAIL_AUTH');
      rethrow;
    } on PlatformException catch (e, st) {
      debugPrint(
        'EMAIL_AUTH: PlatformException code=${e.code} message=${e.message} '
        'details=${e.details}',
      );
      debugPrintStack(stackTrace: st, label: 'EMAIL_AUTH');
      rethrow;
    } catch (e, st) {
      debugPrint('EMAIL_AUTH: Unknown error: $e');
      debugPrintStack(stackTrace: st, label: 'EMAIL_AUTH');
      rethrow;
    }
  }

  static String userMessageForError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'Enter a valid email address.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'user-not-found':
          return 'No account found for this email.';
        case 'wrong-password':
          return 'Incorrect password. Please try again.';
        case 'email-already-in-use':
          return 'That email is already in use. Try signing in instead.';
        case 'weak-password':
          return 'Password is too weak. Use at least 6 characters.';
        case 'operation-not-allowed':
          return 'Email/password sign-in is disabled in Firebase Console.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        default:
          return error.message ?? 'Authentication failed. Please try again.';
      }
    }
    if (error is PlatformException) {
      return error.message ?? 'Authentication failed. Please try again.';
    }
    return 'Authentication failed. Please try again.';
  }
}
