import 'package:flutter/material.dart';

import '../auth/google_auth_service.dart';
import '../widgets/forest_background.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<int>? onSelectTab;

  const HomeScreen({super.key, this.onSelectTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GoogleAuthService _authService = GoogleAuthService();
  bool _isSigningOut = false;

  void _goTo(BuildContext context, String route) {
    final onSelectTab = widget.onSelectTab;
    if (onSelectTab != null) {
      switch (route) {
        case '/observations':
          onSelectTab(1);
          return;
        case '/species-library':
          onSelectTab(2);
          return;
        case '/map':
          onSelectTab(3);
          return;
        case '/settings':
          onSelectTab(4);
          return;
      }
    }
    Navigator.of(context).pushNamed(route);
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

  Future<void> _handleSignOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);
    try {
      await _authService.signOut();
      if (!mounted) return;
      _showToast('Signed out.');
    } catch (_) {
      if (!mounted) return;
      _showToast('Sign-out failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);
    const buttonColor = Color(0xFF8FBFA1);

    return Scaffold(
      body: ForestBackground(
        backgroundAsset: 'assets/images/welcome_bg.png',
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool twoColumns = constraints.maxWidth >= 520;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: _isSigningOut ? null : _handleSignOut,
                        tooltip: 'Sign out',
                        icon: _isSigningOut
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.logout,
                                color: Colors.white,
                              ),
                      ),
                    ],
                  ),
                  const Text(
                    'Australia',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '(Offline AI)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: accentTextColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF7CD39A),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'On-device AI ready',
                        style: TextStyle(
                          fontSize: 14,
                          color: accentTextColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _goTo(context, '/detect'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        'Start Detection',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Explore',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: twoColumns ? 2 : 1,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: twoColumns ? 2.8 : 3.4,
                    children: [
                      _HomeActionCard(
                        title: 'My Observations',
                        subtitle: 'Review your saved finds',
                        icon: Icons.collections_bookmark,
                        onTap: () => _goTo(context, '/observations'),
                      ),
                      _HomeActionCard(
                        title: 'Species Library',
                        subtitle: 'Australia-wide field guide',
                        icon: Icons.menu_book,
                        onTap: () => _goTo(context, '/species-library'),
                      ),
                      _HomeActionCard(
                        title: 'Observation Map',
                        subtitle: 'View mapped finds',
                        icon: Icons.map,
                        onTap: () => _goTo(context, '/map'),
                      ),
                      _HomeActionCard(
                        title: 'Field Notes',
                        subtitle: 'Offline notes and photos',
                        icon: Icons.note_alt,
                        onTap: () => _goTo(context, '/field-notes'),
                      ),
                      _HomeActionCard(
                        title: 'Settings',
                        subtitle: 'Tune on-device preferences',
                        icon: Icons.settings,
                        onTap: () => _goTo(context, '/settings'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _HomeActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x332C6E52),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xCCFFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
