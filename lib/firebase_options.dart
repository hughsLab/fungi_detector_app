import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'config/app_secrets.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static FirebaseOptions get web => FirebaseOptions(
    apiKey: AppSecrets.firebaseWebApiKey,
    appId: AppSecrets.firebaseWebAppId,
    messagingSenderId: AppSecrets.firebaseWebMessagingSenderId,
    projectId: AppSecrets.firebaseWebProjectId,
    authDomain: AppSecrets.firebaseWebAuthDomain,
    storageBucket: AppSecrets.firebaseWebStorageBucket,
    measurementId: AppSecrets.firebaseWebMeasurementId,
  );

  static FirebaseOptions get android => FirebaseOptions(
    apiKey: AppSecrets.firebaseAndroidApiKey,
    appId: AppSecrets.firebaseAndroidAppId,
    messagingSenderId: AppSecrets.firebaseAndroidMessagingSenderId,
    projectId: AppSecrets.firebaseAndroidProjectId,
    storageBucket: AppSecrets.firebaseAndroidStorageBucket,
  );

  static FirebaseOptions get ios => FirebaseOptions(
    apiKey: AppSecrets.firebaseIosApiKey,
    appId: AppSecrets.firebaseIosAppId,
    messagingSenderId: AppSecrets.firebaseIosMessagingSenderId,
    projectId: AppSecrets.firebaseIosProjectId,
    storageBucket: AppSecrets.firebaseIosStorageBucket,
    iosBundleId: AppSecrets.firebaseIosBundleId,
  );

  static FirebaseOptions get macos => FirebaseOptions(
    apiKey: AppSecrets.firebaseMacosApiKey,
    appId: AppSecrets.firebaseMacosAppId,
    messagingSenderId: AppSecrets.firebaseMacosMessagingSenderId,
    projectId: AppSecrets.firebaseMacosProjectId,
    storageBucket: AppSecrets.firebaseMacosStorageBucket,
    iosBundleId: AppSecrets.firebaseMacosBundleId,
  );

  static FirebaseOptions get windows => FirebaseOptions(
    apiKey: AppSecrets.firebaseWindowsApiKey,
    appId: AppSecrets.firebaseWindowsAppId,
    messagingSenderId: AppSecrets.firebaseWindowsMessagingSenderId,
    projectId: AppSecrets.firebaseWindowsProjectId,
    authDomain: AppSecrets.firebaseWindowsAuthDomain,
    storageBucket: AppSecrets.firebaseWindowsStorageBucket,
    measurementId: AppSecrets.firebaseWindowsMeasurementId,
  );
}
