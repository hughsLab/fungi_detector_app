import 'package:flutter/material.dart';

import '../models/navigation_args.dart';
import '../services/settings_service.dart';
import '../widgets/forest_background.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    _routeFromStartup();
  }

  Future<void> _routeFromStartup() async {
    final settings = await SettingsService.instance.loadSettings();
    if (!mounted) return;
    if (!settings.disclaimerAcknowledged) {
      Navigator.of(context).pushReplacementNamed(
        '/disclaimer',
        arguments: const DisclaimerArgs(
          nextRoute: '/auth',
          allowBack: false,
        ),
      );
      return;
    }
    Navigator.of(context).pushReplacementNamed('/auth');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: ForestBackground(
        padding: EdgeInsets.all(0),
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }
}
