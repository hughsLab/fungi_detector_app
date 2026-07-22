import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'debug/detection_batch_test_runner.dart';
import 'firebase_options.dart';
import 'screens/about_screen.dart';
import 'screens/choose_username_screen.dart';
import 'screens/detection_page.dart';
import 'screens/detection_result_screen.dart';
import 'screens/disclaimer_screen.dart';
import 'screens/field_note_editor_screen.dart';
import 'screens/field_notes_screen.dart';
import 'screens/main_shell_screen.dart';
import 'screens/map_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/observations_screen.dart';
import 'screens/online_identification_result_screen.dart';
import 'screens/save_observation_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signin_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/species_detail_screen.dart';
import 'screens/species_library_screen.dart';
import 'screens/startup_screen.dart';
import 'screens/welcome_screen.dart';
import 'repositories/user_profile_repository.dart';
import 'services/auth_service.dart';
import 'services/map_tile_cache_service.dart';
import 'services/settings_service.dart';
import 'services/sync_manager.dart';

const String _expectedAndroidPackageName = 'com.example.app1';
const bool _detectionBatchTest = bool.fromEnvironment('DETECTION_BATCH_TEST');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    debugPrint('FLUTTER_ERROR: ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrintStack(stackTrace: details.stack, label: 'FLUTTER_ERROR');
    }
    FlutterError.presentError(details);
  };
  if (_detectionBatchTest) {
    await DetectionBatchTestRunner().runAndExit();
    return;
  }
  debugPrint('FIREBASE_INIT: initializing Firebase');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('FIREBASE_INIT: Firebase initialized OK');
  _logFirebaseOptions(DefaultFirebaseOptions.currentPlatform);
  await _logSanityDiagnostics();
  await AuthService.instance.initialize();
  await SyncManager.instance.initialize();
  final settings = await SettingsService.instance.loadSettings();
  final int mapCacheCapMb = settings.mapTileCacheMaxSizeMb;
  await MapTileCacheService.instance.ensureInitialized(
    cacheSoftLimitMb: mapCacheCapMb,
    maxDatabaseSizeKiB: mapCacheCapMb * 1024,
  );
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
        '/choose-username': (context) => const ChooseUsernameScreen(),
        '/welcome': (context) => const WelcomeScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/signin': (context) => const SignInScreen(),
        '/home': (context) => const MainShellScreen(),
        '/detect': (context) => const DetectionPage(),
        '/detection-result': (context) => const DetectionResultScreen(),
        '/online-identification-result': (context) =>
            const OnlineIdentificationResultScreen(),
        '/species-library': (context) => const SpeciesLibraryScreen(),
        '/species-detail': (context) => const SpeciesDetailScreen(),
        '/field-notes': (context) => const FieldNotesScreen(),
        '/field-note-editor': (context) => const FieldNoteEditorScreen(),
        '/save-observation': (context) => const SaveObservationScreen(),
        '/observations': (context) => const ObservationsScreen(),
        '/map': (context) => const MapScreen(),
        '/insights': (context) => const InsightsScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/disclaimer': (context) => const DisclaimerScreen(),
        '/about': (context) => const AboutScreen(),
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<void> _initializeFuture;
  final AuthService _authService = AuthService.instance;
  final UserProfileRepository _userProfileRepository =
      UserProfileRepository.instance;
  String? _skippedUsernameUid;

  @override
  void initState() {
    super.initState();
    _initializeFuture = _authService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, initSnapshot) {
        if (initSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return StreamBuilder<AppAuthState>(
          stream: _authService.authStateChanges(),
          initialData: _authService.currentState,
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final authState = authSnapshot.data;
            if (authState == null || !authState.isAuthenticated) {
              return const WelcomeScreen();
            }
            if (authState.isOfflineSession) {
              return const MainShellScreen();
            }
            return FutureBuilder(
              future: _userProfileRepository.ensureUserProfile(),
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final profile = profileSnapshot.data;
                if (profile != null &&
                    !profile.hasUsername &&
                    _skippedUsernameUid != authState.uid) {
                  return ChooseUsernameScreen(
                    allowSkip: true,
                    onSkip: () {
                      setState(() => _skippedUsernameUid = authState.uid);
                    },
                    onSaved: () {
                      setState(() => _skippedUsernameUid = null);
                    },
                  );
                }
                return const MainShellScreen();
              },
            );
          },
        );
      },
    );
  }
}

void _logFirebaseOptions(FirebaseOptions options) {
  if (!kDebugMode) return;
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
  if (!kDebugMode) return;
  debugPrint('SANITY: platform=${defaultTargetPlatform.name} kIsWeb=$kIsWeb');
  final currentUser = FirebaseAuth.instance.currentUser;
  debugPrint(
    'SANITY: firebaseApp=${Firebase.app().name} '
    'projectId=${Firebase.app().options.projectId} '
    'signedIn=${currentUser != null} uidPresent=${currentUser?.uid.isNotEmpty == true}',
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
