import 'package:flutter/material.dart';

import '../widgets/simple_nav_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleNavScreen(
      title: 'Welcome',
      label: 'Welcome Screen',
      backRoute: '/signin',
      forwardRoute: '/signup',
      backgroundAsset: 'assets/images/welcome_bg.png',
    );
  }
}
