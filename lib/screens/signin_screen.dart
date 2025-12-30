import 'package:flutter/material.dart';

import '../widgets/simple_nav_screen.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleNavScreen(
      title: 'Sign In',
      label: 'Sign In Screen',
      backRoute: '/signup',
      forwardRoute: '/',
    );
  }
}
