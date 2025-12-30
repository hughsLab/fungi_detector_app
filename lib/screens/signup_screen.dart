import 'package:flutter/material.dart';

import '../widgets/simple_nav_screen.dart';

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleNavScreen(
      title: 'Sign Up',
      label: 'Sign Up Screen',
      backRoute: '/',
      forwardRoute: '/signin',
    );
  }
}
