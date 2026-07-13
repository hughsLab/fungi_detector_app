import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../repositories/user_profile_repository.dart';
import 'app_toast_service.dart';

enum AppAuthSource { firebase, cache, none }

class AppAuthState {
  final bool isAuthenticated;
  final bool isOfflineSession;
  final bool isOnline;
  final String? uid;
  final AppAuthSource source;
  final String? reason;

  const AppAuthState({
    required this.isAuthenticated,
    required this.isOfflineSession,
    required this.isOnline,
    required this.uid,
    required this.source,
    required this.reason,
  });

  const AppAuthState.unauthenticated({required bool isOnline, String? reason})
    : this(
        isAuthenticated: false,
        isOfflineSession: false,
        isOnline: isOnline,
        uid: null,
        source: AppAuthSource.none,
        reason: reason,
      );

  const AppAuthState.firebaseAuthenticated({
    required bool isOnline,
    required String uid,
  }) : this(
         isAuthenticated: true,
         isOfflineSession: false,
         isOnline: isOnline,
         uid: uid,
         source: AppAuthSource.firebase,
         reason: null,
       );

  const AppAuthState.cachedOfflineAuthenticated({
    required String uid,
    String? reason,
  }) : this(
         isAuthenticated: true,
         isOfflineSession: true,
         isOnline: false,
         uid: uid,
         source: AppAuthSource.cache,
         reason: reason,
       );
}

class _CachedAuthSession {
  final String uid;
  final String? idToken;
  final DateTime? expiresAt;

  const _CachedAuthSession({
    required this.uid,
    required this.idToken,
    required this.expiresAt,
  });
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const String _uidKey = 'auth_cached_uid';
  static const String _tokenKey = 'auth_cached_id_token';
  static const String _tokenExpiryKey = 'auth_cached_token_expiry_ms';
  static const String _tokenCachedAtKey = 'auth_cached_token_cached_at_ms';

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Connectivity _connectivity = Connectivity();

  final StreamController<AppAuthState> _authStateController =
      StreamController<AppAuthState>.broadcast();

  StreamSubscription<User?>? _firebaseAuthSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  AppAuthState _currentState = const AppAuthState.unauthenticated(
    isOnline: true,
  );
  _CachedAuthSession? _cachedSession;
  bool _isOnline = true;
  bool _initialized = false;
  bool _offlineLoginToastShownThisRun = false;
  Future<void>? _initializeFuture;

  AppAuthState get currentState => _currentState;
  bool get isOnline => _isOnline;

  Future<void> initialize() {
    _initializeFuture ??= _initializeInternal();
    return _initializeFuture!;
  }

  Stream<AppAuthState> authStateChanges() async* {
    await initialize();
    yield _currentState;
    yield* _authStateController.stream;
  }

  Future<bool> ensureLoginPossibleOrNotify() async {
    await initialize();
    if (_isOnline) {
      return true;
    }
    if (_isCachedSessionValid(_cachedSession)) {
      return true;
    }
    await _showOfflineLoginRequiredToast();
    return false;
  }

  Future<bool> hasValidCachedSession() async {
    await initialize();
    return _isCachedSessionValid(_cachedSession);
  }

  Future<void> cacheFirebaseUserSession(User? user) async {
    if (user == null) return;
    try {
      final tokenResult = await user.getIdTokenResult();
      final expiry = tokenResult.expirationTime;
      final now = DateTime.now();
      await _secureStorage.write(key: _uidKey, value: user.uid);
      await _secureStorage.write(key: _tokenKey, value: tokenResult.token);
      await _secureStorage.write(
        key: _tokenExpiryKey,
        value: expiry?.millisecondsSinceEpoch.toString(),
      );
      await _secureStorage.write(
        key: _tokenCachedAtKey,
        value: now.millisecondsSinceEpoch.toString(),
      );
      _cachedSession = _CachedAuthSession(
        uid: user.uid,
        idToken: tokenResult.token,
        expiresAt: expiry,
      );
      await _emitState(firebaseUserOverride: user);
    } catch (e, st) {
      debugPrint('AUTH: Failed caching auth session: $e');
      debugPrintStack(stackTrace: st, label: 'AUTH');
    }
  }

  Future<void> clearCachedSession() async {
    await Future.wait([
      _secureStorage.delete(key: _uidKey),
      _secureStorage.delete(key: _tokenKey),
      _secureStorage.delete(key: _tokenExpiryKey),
      _secureStorage.delete(key: _tokenCachedAtKey),
    ]);
    _cachedSession = null;
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    await clearCachedSession();
    await _emitState(firebaseUserOverride: null);
  }

  Future<void> maybeNotifyOfflineNoCachedSession() async {
    await initialize();
    if (_isOnline) {
      return;
    }
    if (_isCachedSessionValid(_cachedSession)) {
      return;
    }
    await _showOfflineLoginRequiredToast();
  }

  Future<void> dispose() async {
    await _firebaseAuthSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _authStateController.close();
    _firebaseAuthSubscription = null;
    _connectivitySubscription = null;
    _initialized = false;
    _initializeFuture = null;
  }

  Future<void> _initializeInternal() async {
    if (_initialized) return;

    _isOnline = await _checkOnline();
    _cachedSession = await _readCachedSession();

    _firebaseAuthSubscription = _firebaseAuth.idTokenChanges().listen((
      firebaseUser,
    ) async {
      if (firebaseUser != null) {
        await _ensureUserProfile(firebaseUser);
        await cacheFirebaseUserSession(firebaseUser);
      } else if (_isOnline) {
        await clearCachedSession();
      }
      await _emitState(firebaseUserOverride: firebaseUser);
    });

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) async {
      final wasOffline = !_isOnline;
      _isOnline = _isConnected(results);
      _logConnectivityChange(results, _isOnline);
      if (_isOnline && wasOffline) {
        _offlineLoginToastShownThisRun = false;
      }
      await _emitState();
    });

    _initialized = true;
    await _emitState();
  }

  Future<void> _emitState({User? firebaseUserOverride}) async {
    final firebaseUser = firebaseUserOverride ?? _firebaseAuth.currentUser;

    late final AppAuthState nextState;
    if (firebaseUser != null) {
      nextState = AppAuthState.firebaseAuthenticated(
        isOnline: _isOnline,
        uid: firebaseUser.uid,
      );
    } else {
      _cachedSession ??= await _readCachedSession();
      if (!_isOnline && _isCachedSessionValid(_cachedSession)) {
        nextState = AppAuthState.cachedOfflineAuthenticated(
          uid: _cachedSession!.uid,
          reason: 'Offline mode: using cached authenticated session.',
        );
      } else if (!_isOnline) {
        nextState = const AppAuthState.unauthenticated(
          isOnline: false,
          reason: 'Offline and no valid cached session available.',
        );
      } else {
        nextState = const AppAuthState.unauthenticated(
          isOnline: true,
          reason: null,
        );
      }
    }

    _currentState = nextState;
    if (!_authStateController.isClosed) {
      _authStateController.add(nextState);
    }
  }

  Future<void> _ensureUserProfile(User user) async {
    try {
      await UserProfileRepository.instance.ensureUserProfile(user: user);
    } catch (e, st) {
      debugPrint('AUTH: Failed ensuring user profile: $e');
      debugPrintStack(stackTrace: st, label: 'AUTH');
    }
  }

  Future<bool> _checkOnline() async {
    final results = await _connectivity.checkConnectivity();
    final connected = _isConnected(results);
    if (kDebugMode) {
      debugPrint(
        'AUTH: connectivity check results='
        '${results.map((result) => result.name).join(',')} '
        'connected=$connected',
      );
    }
    return connected;
  }

  bool _isConnected(List<ConnectivityResult> results) {
    for (final result in results) {
      if (result != ConnectivityResult.none) {
        return true;
      }
    }
    return false;
  }

  void _logConnectivityChange(List<ConnectivityResult> results, bool connected) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      'AUTH: connectivity changed results='
      '${results.map((result) => result.name).join(',')} '
      'connected=$connected',
    );
  }

  Future<_CachedAuthSession?> _readCachedSession() async {
    try {
      final uid = await _secureStorage.read(key: _uidKey);
      if (uid == null || uid.trim().isEmpty) {
        return null;
      }

      final token = await _secureStorage.read(key: _tokenKey);
      final expiryRaw = await _secureStorage.read(key: _tokenExpiryKey);
      final cachedAtRaw = await _secureStorage.read(key: _tokenCachedAtKey);

      DateTime? expiresAt;
      if (expiryRaw != null) {
        final parsed = int.tryParse(expiryRaw);
        if (parsed != null) {
          expiresAt = DateTime.fromMillisecondsSinceEpoch(parsed);
        }
      } else if (cachedAtRaw != null) {
        final parsed = int.tryParse(cachedAtRaw);
        if (parsed != null) {
          // Fallback for old/partial cache records.
          expiresAt = DateTime.fromMillisecondsSinceEpoch(
            parsed,
          ).add(const Duration(hours: 12));
        }
      }

      return _CachedAuthSession(uid: uid, idToken: token, expiresAt: expiresAt);
    } catch (e, st) {
      debugPrint('AUTH: Failed reading cached session: $e');
      debugPrintStack(stackTrace: st, label: 'AUTH');
      return null;
    }
  }

  bool _isCachedSessionValid(_CachedAuthSession? session) {
    if (session == null || session.uid.trim().isEmpty) {
      return false;
    }
    final expiry = session.expiresAt;
    if (expiry == null) {
      return false;
    }
    return DateTime.now().isBefore(expiry.subtract(const Duration(minutes: 2)));
  }

  Future<void> _showOfflineLoginRequiredToast() async {
    if (_offlineLoginToastShownThisRun) {
      return;
    }
    _offlineLoginToastShownThisRun = true;
    await AppToastService.show(
      'You are offline. Connect to the internet to log in.',
    );
  }
}
