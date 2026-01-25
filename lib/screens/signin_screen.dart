import 'package:flutter/material.dart';

import '../auth/email_auth_service.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final EmailAuthService _authService = EmailAuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSigningIn = false;
  bool _isResetting = false;

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

  bool _validateEmail(String email) {
    if (email.isEmpty) {
      _showToast('Email is required.');
      return false;
    }
    if (!_emailRegex.hasMatch(email)) {
      _showToast('Enter a valid email address.');
      return false;
    }
    return true;
  }

  bool _validatePassword(String password) {
    if (password.isEmpty) {
      _showToast('Password is required.');
      return false;
    }
    if (password.length < 6) {
      _showToast('Password must be at least 6 characters.');
      return false;
    }
    return true;
  }

  Future<void> _handleEmailSignIn() async {
    if (_isSigningIn) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!_validateEmail(email) || !_validatePassword(password)) {
      return;
    }
    setState(() => _isSigningIn = true);
    try {
      final credential = await _authService.signInWithEmailPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;
      final userEmail = credential.user?.email;
      _showToast(
        userEmail == null ? 'Signed in successfully.' : 'Signed in as $userEmail',
      );
      _goTo(context, '/home');
    } catch (error) {
      if (!mounted) return;
      _showToast(EmailAuthService.userMessageForError(error));
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  Future<void> _handlePasswordReset() async {
    if (_isResetting) return;
    final email = _emailController.text.trim();
    if (!_validateEmail(email)) {
      return;
    }
    setState(() => _isResetting = true);
    try {
      await _authService.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      _showToast('Password reset email sent.');
    } catch (error) {
      if (!mounted) return;
      _showToast(EmailAuthService.userMessageForError(error));
    } finally {
      if (mounted) {
        setState(() => _isResetting = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
                            'Sign In',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Sign In now to access your exercises and saved music.',
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.4,
                              color: accentTextColor,
                            ),
                          ),
                          const SizedBox(height: 36),
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
                          const SizedBox(height: 24),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) =>
                                _isSigningIn ? null : _handleEmailSignIn(),
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
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: (_isSigningIn || _isResetting)
                                  ? null
                                  : _handlePasswordReset,
                              style: TextButton.styleFrom(
                                foregroundColor: accentTextColor,
                              ),
                              child: Text(
                                _isResetting
                                    ? 'Sending reset...'
                                    : 'Forgot password?',
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  _isSigningIn ? null : _handleEmailSignIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: buttonColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: const StadiumBorder(),
                              ),
                              child: Text(
                                _isSigningIn ? 'Signing In...' : 'Sign In',
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
                              onTap: () => _goTo(context, '/signup'),
                              child: const Text.rich(
                                TextSpan(
                                  text: "Don't have an account? ",
                                  style: TextStyle(
                                    color: accentTextColor,
                                    fontSize: 14,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'Sign Up',
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
