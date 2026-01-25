import 'package:flutter/material.dart';

import '../auth/email_auth_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final EmailAuthService _authService = EmailAuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isSigningUp = false;

  static final RegExp _emailRegex =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void _goTo(BuildContext context, String route) {
    Navigator.of(context).pushReplacementNamed(route);
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _validateInputs({
    required String email,
    required String password,
    required String confirmPassword,
  }) {
    if (email.isEmpty) {
      _showToast('Email is required.');
      return false;
    }
    if (!_emailRegex.hasMatch(email)) {
      _showToast('Enter a valid email address.');
      return false;
    }
    if (password.isEmpty) {
      _showToast('Password is required.');
      return false;
    }
    if (password.length < 6) {
      _showToast('Password must be at least 6 characters.');
      return false;
    }
    if (confirmPassword.isEmpty) {
      _showToast('Confirm your password.');
      return false;
    }
    if (password != confirmPassword) {
      _showToast('Passwords do not match.');
      return false;
    }
    return true;
  }

  Future<void> _handleEmailSignUp() async {
    if (_isSigningUp) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    if (!_validateInputs(
      email: email,
      password: password,
      confirmPassword: confirmPassword,
    )) {
      return;
    }
    setState(() => _isSigningUp = true);
    try {
      final credential = await _authService.signUpWithEmailPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (!mounted) return;
      if (user != null && !user.emailVerified) {
        try {
          await _authService.sendEmailVerification(user: user);
          if (!mounted) return;
          _showToast('Account created. Check your inbox to verify.');
        } catch (error) {
          if (!mounted) return;
          _showToast(EmailAuthService.userMessageForError(error));
        }
      } else {
        final userEmail = user?.email;
        _showToast(
          userEmail == null
              ? 'Account created.'
              : 'Account created for $userEmail',
        );
      }
      _goTo(context, '/home');
    } catch (error) {
      if (!mounted) return;
      _showToast(EmailAuthService.userMessageForError(error));
    } finally {
      if (mounted) {
        setState(() => _isSigningUp = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF1F4E3D);
    const accentTextColor = Color(0xCCFFFFFF);
    const buttonColor = Color(0xFF8FBFA1);
    const backgroundScale = 0.9;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: backgroundColor),
          Positioned.fill(
            child: SafeArea(
              child: Transform.scale(
                scale: backgroundScale,
                child: Image.asset(
                  'assets/images/bg1.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Align(
                      alignment: const Alignment(-1.0, -0.2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 110,
                            width: 110,
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'Sign Up',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Sign up now to find, explore and identify.',
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.4,
                              color: accentTextColor,
                            ),
                          ),
                          const SizedBox(height: 32),
                          TextField(
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                              labelStyle: TextStyle(color: accentTextColor),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: accentTextColor),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              labelStyle: TextStyle(color: accentTextColor),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: accentTextColor),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              labelStyle: TextStyle(color: accentTextColor),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: accentTextColor),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          TextField(
                            controller: _confirmPasswordController,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) =>
                                _isSigningUp ? null : _handleEmailSignUp(),
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Confirm Password',
                              labelStyle: TextStyle(color: accentTextColor),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: accentTextColor),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  _isSigningUp ? null : _handleEmailSignUp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: buttonColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: const StadiumBorder(),
                              ),
                              child: Text(
                                _isSigningUp ? 'Signing Up...' : 'Sign Up',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => _goTo(context, '/home'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white70),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: const StadiumBorder(),
                              ),
                              child: const Text(
                                'Continue Without Account',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Center(
                            child: GestureDetector(
                              onTap: () => _goTo(context, '/signin'),
                              child: const Text.rich(
                                TextSpan(
                                  text: 'Already have an account? ',
                                  style: TextStyle(
                                    color: accentTextColor,
                                    fontSize: 14,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'Sign In',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
