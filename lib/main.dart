import 'package:flutter/material.dart';

import 'screens/about_screen.dart';
import 'screens/detection_page.dart';
import 'screens/detection_result_screen.dart';
import 'screens/disclaimer_screen.dart';
import 'screens/home_screen.dart';
import 'screens/observations_screen.dart';
import 'screens/save_observation_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signin_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/species_detail_screen.dart';
import 'screens/species_library_screen.dart';
import 'screens/startup_screen.dart';
import 'screens/welcome_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        '/welcome': (context) => const WelcomeScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/signin': (context) => const SignInScreen(),
        '/home': (context) => const HomeScreen(),
        '/detect': (context) => const DetectionPage(),
        '/detection-result': (context) => const DetectionResultScreen(),
        '/species-library': (context) => const SpeciesLibraryScreen(),
        '/species-detail': (context) => const SpeciesDetailScreen(),
        '/save-observation': (context) => const SaveObservationScreen(),
        '/observations': (context) => const ObservationsScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/disclaimer': (context) => const DisclaimerScreen(),
        '/about': (context) => const AboutScreen(),
      },
    );
  }
}
