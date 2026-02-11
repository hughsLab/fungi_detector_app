import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'firebase_options.dart';
import 'screens/about_screen.dart';
import 'screens/detection_page.dart';
import 'screens/detection_result_screen.dart';
import 'screens/disclaimer_screen.dart';
import 'screens/main_shell_screen.dart';
import 'screens/map_screen.dart';
import 'screens/observations_screen.dart';
import 'screens/save_observation_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signin_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/species_detail_screen.dart';
import 'screens/species_library_screen.dart';
import 'screens/startup_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/map_tile_cache_service.dart';

const String _expectedAndroidPackageName = 'com.example.app1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    debugPrint('FLUTTER_ERROR: ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrintStack(stackTrace: details.stack, label: 'FLUTTER_ERROR');
    }
    FlutterError.presentError(details);
  };
  debugPrint('FIREBASE_INIT: initializing Firebase');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('FIREBASE_INIT: Firebase initialized OK');
  _logFirebaseOptions(DefaultFirebaseOptions.currentPlatform);
  await _logSanityDiagnostics();
  await MapTileCacheService.instance.ensureInitialized();
  runApp(const RealtimeDetectionApp());
}

class RealtimeDetectionApp extends StatelessWidget {
  const RealtimeDetectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Realtime Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/startup',
      routes: {
        '/startup': (context) => const StartupScreen(),
        '/auth': (context) => const AuthGate(),
        '/welcome': (context) => const WelcomeScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/signin': (context) => const SignInScreen(),
        '/home': (context) => const MainShellScreen(),
        '/detect': (context) => const DetectionPage(),
        '/detection-result': (context) => const DetectionResultScreen(),
        '/species-library': (context) => const SpeciesLibraryScreen(),
        '/species-detail': (context) => const SpeciesDetailScreen(),
        '/save-observation': (context) => const SaveObservationScreen(),
        '/observations': (context) => const ObservationsScreen(),
        '/map': (context) => const MapScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/disclaimer': (context) => const DisclaimerScreen(),
        '/about': (context) => const AboutScreen(),
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const WelcomeScreen();
        }

        return const MainShellScreen();
      },
    );
  }
}

void _logFirebaseOptions(FirebaseOptions options) {
  debugPrint(
    'FIREBASE_INIT: options projectId=${options.projectId} '
    'appId=${options.appId} messagingSenderId=${options.messagingSenderId} '
    'apiKey=*** authDomain=${options.authDomain ?? "-"} '
    'storageBucket=${options.storageBucket ?? "-"} '
    'measurementId=${options.measurementId ?? "-"} '
    'iosBundleId=${options.iosBundleId ?? "-"} '
    'androidClientId=${options.androidClientId ?? "-"} '
    'iosClientId=${options.iosClientId ?? "-"}',
  );
}

Future<void> _logSanityDiagnostics() async {
  debugPrint(
    'SANITY: platform=${defaultTargetPlatform.name} kIsWeb=$kIsWeb',
  );
  final currentUser = FirebaseAuth.instance.currentUser;
  debugPrint(
    'SANITY: currentUser uid=${currentUser?.uid} email=${currentUser?.email}',
  );
  try {
    final info = await PackageInfo.fromPlatform();
    debugPrint(
      'SANITY: packageName=${info.packageName} '
      'version=${info.version} build=${info.buildNumber}',
    );
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (info.packageName != _expectedAndroidPackageName) {
        debugPrint(
          'ANDROID_CONFIG: applicationId mismatch. '
          'expected=$_expectedAndroidPackageName actual=${info.packageName}',
        );
      } else {
        debugPrint(
          'ANDROID_CONFIG: applicationId matches $_expectedAndroidPackageName',
        );
      }
      debugPrint(
        'ANDROID_CONFIG: ensure `com.google.gms.google-services` plugin is '
        'applied in android/app/build.gradle.kts',
      );
    }
  } catch (e, st) {
    debugPrint('SANITY: package info lookup failed: $e');
    debugPrintStack(stackTrace: st, label: 'SANITY');
  }
}
