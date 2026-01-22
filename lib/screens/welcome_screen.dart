import 'package:flutter/material.dart';

import '../auth/google_auth_service.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final GoogleAuthService _authService = GoogleAuthService();
  bool _isSigningIn = false;

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

  Future<void> _handleGoogleSignIn() async {
    if (_isSigningIn) return;
    setState(() => _isSigningIn = true);
    try {
      final credential = await _authService.signInWithGoogleDebug();
      if (!mounted) return;
      if (credential == null) {
        _showToast('Sign-in cancelled.');
        return;
      }
      final email = credential.user?.email;
      _showToast(
        email == null ? 'Signed in successfully.' : 'Signed in as $email',
      );
    } catch (error) {
      if (!mounted) return;
      _showToast(GoogleAuthService.userMessageForError(error));
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xDFFFFFFF);
    const buttonColor = Color(0xFF8FBFA1);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/welcome_bg.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x551F4E3D),
                  Color(0xB31F4E3D),
                ],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool useSpacer = constraints.maxHeight >= 720;
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        height: useSpacer ? constraints.maxHeight : null,
                        child: Column(
                          mainAxisSize:
                              useSpacer ? MainAxisSize.max : MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 110,
                              width: 110,
                              child: Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'WELCOME',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (useSpacer)
                              const Spacer()
                            else
                              const SizedBox(height: 24),
                            const Text(
                              'Welcome to Australian Fungi Identifier',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Identify and explore Australian mushrooms and fungi '
                              'in real time using offline, on-device AI.\n\n'
                              'Create an account to identify, record, and discover ',
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.45,
                                color: accentTextColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (useSpacer)
                              const Spacer()
                            else
                              const SizedBox(height: 32),
                            Center(
                              child: SizedBox(
                                height: 54,
                                child: TextButton(
                                  onPressed:
                                      _isSigningIn ? null : _handleGoogleSignIn,
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Opacity(
                                        opacity: _isSigningIn ? 0.6 : 1,
                                        child: Image.asset(
                                          'assets/images/android_dark_rd_ctn_4x.png',
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      if (_isSigningIn)
                                        const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _goTo(context, '/signin'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: buttonColor,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: const StadiumBorder(),
                                ),
                              child: const Text(
                                'Sign In With Email',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
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
                            const SizedBox(height: 16),
                            GestureDetector(
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
                          ],
                        ),
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
