import 'package:flutter/foundation.dart';

class AppSecrets {
  static const _firebaseAndroidApiKey =
      String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  static const _firebaseAndroidAppId =
      String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const _firebaseAndroidMessagingSenderId =
      String.fromEnvironment('FIREBASE_ANDROID_MESSAGING_SENDER_ID');
  static const _firebaseAndroidProjectId =
      String.fromEnvironment('FIREBASE_ANDROID_PROJECT_ID');
  static const _firebaseAndroidStorageBucket =
      String.fromEnvironment('FIREBASE_ANDROID_STORAGE_BUCKET');

  static const _firebaseIosApiKey =
      String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const _firebaseIosAppId =
      String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _firebaseIosMessagingSenderId =
      String.fromEnvironment('FIREBASE_IOS_MESSAGING_SENDER_ID');
  static const _firebaseIosProjectId =
      String.fromEnvironment('FIREBASE_IOS_PROJECT_ID');
  static const _firebaseIosStorageBucket =
      String.fromEnvironment('FIREBASE_IOS_STORAGE_BUCKET');
  static const _firebaseIosBundleId =
      String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  static const _firebaseMacosApiKey =
      String.fromEnvironment('FIREBASE_MACOS_API_KEY');
  static const _firebaseMacosAppId =
      String.fromEnvironment('FIREBASE_MACOS_APP_ID');
  static const _firebaseMacosMessagingSenderId =
      String.fromEnvironment('FIREBASE_MACOS_MESSAGING_SENDER_ID');
  static const _firebaseMacosProjectId =
      String.fromEnvironment('FIREBASE_MACOS_PROJECT_ID');
  static const _firebaseMacosStorageBucket =
      String.fromEnvironment('FIREBASE_MACOS_STORAGE_BUCKET');
  static const _firebaseMacosBundleId =
      String.fromEnvironment('FIREBASE_MACOS_BUNDLE_ID');

  static const _firebaseWebApiKey =
      String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static const _firebaseWebAppId =
      String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _firebaseWebMessagingSenderId =
      String.fromEnvironment('FIREBASE_WEB_MESSAGING_SENDER_ID');
  static const _firebaseWebProjectId =
      String.fromEnvironment('FIREBASE_WEB_PROJECT_ID');
  static const _firebaseWebAuthDomain =
      String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN');
  static const _firebaseWebStorageBucket =
      String.fromEnvironment('FIREBASE_WEB_STORAGE_BUCKET');
  static const _firebaseWebMeasurementId =
      String.fromEnvironment('FIREBASE_WEB_MEASUREMENT_ID');

  static const _firebaseWindowsApiKey =
      String.fromEnvironment('FIREBASE_WINDOWS_API_KEY');
  static const _firebaseWindowsAppId =
      String.fromEnvironment('FIREBASE_WINDOWS_APP_ID');
  static const _firebaseWindowsMessagingSenderId =
      String.fromEnvironment('FIREBASE_WINDOWS_MESSAGING_SENDER_ID');
  static const _firebaseWindowsProjectId =
      String.fromEnvironment('FIREBASE_WINDOWS_PROJECT_ID');
  static const _firebaseWindowsAuthDomain =
      String.fromEnvironment('FIREBASE_WINDOWS_AUTH_DOMAIN');
  static const _firebaseWindowsStorageBucket =
      String.fromEnvironment('FIREBASE_WINDOWS_STORAGE_BUCKET');
  static const _firebaseWindowsMeasurementId =
      String.fromEnvironment('FIREBASE_WINDOWS_MEASUREMENT_ID');

  static const _googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static String get firebaseAndroidApiKey =>
      _require('FIREBASE_ANDROID_API_KEY', _firebaseAndroidApiKey);
  static String get firebaseAndroidAppId =>
      _require('FIREBASE_ANDROID_APP_ID', _firebaseAndroidAppId);
  static String get firebaseAndroidMessagingSenderId =>
      _require(
        'FIREBASE_ANDROID_MESSAGING_SENDER_ID',
        _firebaseAndroidMessagingSenderId,
      );
  static String get firebaseAndroidProjectId =>
      _require('FIREBASE_ANDROID_PROJECT_ID', _firebaseAndroidProjectId);
  static String? get firebaseAndroidStorageBucket =>
      _optional('FIREBASE_ANDROID_STORAGE_BUCKET', _firebaseAndroidStorageBucket);

  static String get firebaseIosApiKey =>
      _require('FIREBASE_IOS_API_KEY', _firebaseIosApiKey);
  static String get firebaseIosAppId =>
      _require('FIREBASE_IOS_APP_ID', _firebaseIosAppId);
  static String get firebaseIosMessagingSenderId =>
      _require(
        'FIREBASE_IOS_MESSAGING_SENDER_ID',
        _firebaseIosMessagingSenderId,
      );
  static String get firebaseIosProjectId =>
      _require('FIREBASE_IOS_PROJECT_ID', _firebaseIosProjectId);
  static String? get firebaseIosStorageBucket =>
      _optional('FIREBASE_IOS_STORAGE_BUCKET', _firebaseIosStorageBucket);
  static String get firebaseIosBundleId =>
      _require('FIREBASE_IOS_BUNDLE_ID', _firebaseIosBundleId);

  static String get firebaseMacosApiKey =>
      _require('FIREBASE_MACOS_API_KEY', _firebaseMacosApiKey);
  static String get firebaseMacosAppId =>
      _require('FIREBASE_MACOS_APP_ID', _firebaseMacosAppId);
  static String get firebaseMacosMessagingSenderId =>
      _require(
        'FIREBASE_MACOS_MESSAGING_SENDER_ID',
        _firebaseMacosMessagingSenderId,
      );
  static String get firebaseMacosProjectId =>
      _require('FIREBASE_MACOS_PROJECT_ID', _firebaseMacosProjectId);
  static String? get firebaseMacosStorageBucket =>
      _optional('FIREBASE_MACOS_STORAGE_BUCKET', _firebaseMacosStorageBucket);
  static String get firebaseMacosBundleId =>
      _require('FIREBASE_MACOS_BUNDLE_ID', _firebaseMacosBundleId);

  static String get firebaseWebApiKey =>
      _require('FIREBASE_WEB_API_KEY', _firebaseWebApiKey);
  static String get firebaseWebAppId =>
      _require('FIREBASE_WEB_APP_ID', _firebaseWebAppId);
  static String get firebaseWebMessagingSenderId =>
      _require(
        'FIREBASE_WEB_MESSAGING_SENDER_ID',
        _firebaseWebMessagingSenderId,
      );
  static String get firebaseWebProjectId =>
      _require('FIREBASE_WEB_PROJECT_ID', _firebaseWebProjectId);
  static String get firebaseWebAuthDomain =>
      _require('FIREBASE_WEB_AUTH_DOMAIN', _firebaseWebAuthDomain);
  static String? get firebaseWebStorageBucket =>
      _optional('FIREBASE_WEB_STORAGE_BUCKET', _firebaseWebStorageBucket);
  static String? get firebaseWebMeasurementId =>
      _optional('FIREBASE_WEB_MEASUREMENT_ID', _firebaseWebMeasurementId);

  static String get firebaseWindowsApiKey =>
      _require('FIREBASE_WINDOWS_API_KEY', _firebaseWindowsApiKey);
  static String get firebaseWindowsAppId =>
      _require('FIREBASE_WINDOWS_APP_ID', _firebaseWindowsAppId);
  static String get firebaseWindowsMessagingSenderId =>
      _require(
        'FIREBASE_WINDOWS_MESSAGING_SENDER_ID',
        _firebaseWindowsMessagingSenderId,
      );
  static String get firebaseWindowsProjectId =>
      _require('FIREBASE_WINDOWS_PROJECT_ID', _firebaseWindowsProjectId);
  static String? get firebaseWindowsAuthDomain =>
      _optional('FIREBASE_WINDOWS_AUTH_DOMAIN', _firebaseWindowsAuthDomain);
  static String? get firebaseWindowsStorageBucket =>
      _optional('FIREBASE_WINDOWS_STORAGE_BUCKET', _firebaseWindowsStorageBucket);
  static String? get firebaseWindowsMeasurementId =>
      _optional('FIREBASE_WINDOWS_MEASUREMENT_ID', _firebaseWindowsMeasurementId);

  static String? get googleWebClientId {
    final value = _optional('GOOGLE_WEB_CLIENT_ID', _googleWebClientId);
    if (kIsWeb && (value == null || value.isEmpty)) {
      throw StateError(
        'Missing required config: GOOGLE_WEB_CLIENT_ID. '
        'Provide via --dart-define or --dart-define-from-file.',
      );
    }
    return value;
  }

  static String requireGoogleWebClientId() =>
      _require('GOOGLE_WEB_CLIENT_ID', _googleWebClientId);

  static String _require(String key, String dartDefineValue) {
    final value = _value(key, dartDefineValue);
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing required config: $key. Provide via --dart-define or '
        '--dart-define-from-file.',
      );
    }
    return value;
  }

  static String? _optional(String key, String dartDefineValue) {
    final value = _value(key, dartDefineValue);
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static String? _value(String key, String dartDefineValue) {
    if (dartDefineValue.isNotEmpty) {
      return dartDefineValue;
    }
    return null;
  }
}
