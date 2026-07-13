import 'dart:async';

import 'package:flutter/material.dart';

import '../repositories/observation_repository.dart';
import '../models/user_profile.dart';
import '../repositories/user_profile_repository.dart';
import '../services/auth_service.dart';
import '../services/country_location_service.dart';
import '../widgets/forest_background.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<int>? onSelectTab;

  const HomeScreen({super.key, this.onSelectTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService.instance;
  final CountryLocationService _countryLocationService =
      CountryLocationService.instance;
  final ObservationRepository _observationRepository =
      ObservationRepository.instance;
  final UserProfileRepository _userProfileRepository =
      UserProfileRepository.instance;

  String _country = CountryLocationService.fallbackCountry;
  int? _observationCount;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCountry());
    unawaited(_loadObservationCount());
  }

  Future<void> _loadCountry() async {
    final cachedCountry =
        await _countryLocationService.getCachedCountryOrFallback();
    if (!mounted) return;
    setState(() => _country = cachedCountry);

    final detectedCountry =
        await _countryLocationService.getCurrentCountryOrFallback();
    if (!mounted || detectedCountry == _country) return;
    setState(() => _country = detectedCountry);
  }

  Future<void> _loadObservationCount() async {
    final observations = await _observationRepository.loadObservations();
    if (!mounted) return;
    setState(() => _observationCount = observations.length);
  }

  void _goTo(BuildContext context, String route) {
    final onSelectTab = widget.onSelectTab;
    if (onSelectTab != null) {
      switch (route) {
        case '/detect':
          onSelectTab(1);
          return;
        case '/observations':
          onSelectTab(2);
          return;
        case '/species-library':
          onSelectTab(3);
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
    return Scaffold(
      backgroundColor: _HomeColors.background,
      body: ForestBackground(
        backgroundAsset: 'assets/images/welcome_bg.png',
        overlayGradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xCCEDE7D9),
            Color(0x8AB5D4C6),
            Color(0xDDEDE8DC),
          ],
          stops: [0.0, 0.44, 1.0],
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 620;

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StreamBuilder<UserProfile?>(
                      stream: _userProfileRepository.streamCurrentUserProfile(),
                      builder: (context, snapshot) {
                        return _HomeHeader(
                          welcomeName: snapshot.data?.welcomeName ?? 'there',
                          country: _country,
                          isSigningOut: _isSigningOut,
                          onSettings: () => _goTo(context, '/settings'),
                          onSignOut: _handleSignOut,
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    _StartDetectionCard(
                      onTap: () => _goTo(context, '/detect'),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Explore',
                      style: TextStyle(
                        fontSize: 22,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: _HomeColors.text,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _ExploreGrid(
                      twoColumns: twoColumns,
                      observationCount: _observationCount,
                      onTapObservations: () => _goTo(context, '/observations'),
                      onTapLibrary: () => _goTo(context, '/species-library'),
                      onTapMap: () => _goTo(context, '/map'),
                      onTapNotes: () => _goTo(context, '/field-notes'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  final String welcomeName;
  final String country;
  final bool isSigningOut;
  final VoidCallback onSettings;
  final VoidCallback onSignOut;

  const _HomeHeader({
    required this.welcomeName,
    required this.country,
    required this.isSigningOut,
    required this.onSettings,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome $welcomeName',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _HomeColors.mutedText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                country,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 32,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  color: _HomeColors.text,
                ),
              ),
              const SizedBox(height: 12),
              const _StatusPill(),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              onPressed: onSettings,
              tooltip: 'Settings',
              style: IconButton.styleFrom(
                backgroundColor: _HomeColors.primary,
                foregroundColor: Colors.white,
                fixedSize: const Size(52, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.settings_rounded),
            ),
            const SizedBox(height: 8),
            IconButton.filledTonal(
              onPressed: isSigningOut ? null : onSignOut,
              tooltip: 'Sign out',
              style: IconButton.styleFrom(
                backgroundColor: _HomeColors.primary,
                foregroundColor: Colors.white,
                fixedSize: const Size(52, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                disabledBackgroundColor: _HomeColors.primary.withValues(
                  alpha: 0.42,
                ),
              ),
              icon: isSigningOut
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
            ),
          ],
        ),
      ],
    );
  }

}

class _StatusPill extends StatelessWidget {
  const _StatusPill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A244A35),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ReadyDot(),
            SizedBox(width: 8),
            Text(
              'On-device AI ready',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _HomeColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyDot extends StatelessWidget {
  const _ReadyDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: _HomeColors.accent,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _StartDetectionCard extends StatelessWidget {
  final VoidCallback onTap;

  const _StartDetectionCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        height: 104,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF3F9362),
              Color(0xFF17643F),
            ],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3D17643F),
              blurRadius: 24,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  child: const Icon(
                    Icons.center_focus_strong_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start Detection',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Identify fungi with on-device AI',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xDFFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 54,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _HomeColors.buttonGreen,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33245D3F),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExploreGrid extends StatelessWidget {
  final bool twoColumns;
  final int? observationCount;
  final VoidCallback onTapObservations;
  final VoidCallback onTapLibrary;
  final VoidCallback onTapMap;
  final VoidCallback onTapNotes;

  const _ExploreGrid({
    required this.twoColumns,
    required this.observationCount,
    required this.onTapObservations,
    required this.onTapLibrary,
    required this.onTapMap,
    required this.onTapNotes,
  });

  @override
  Widget build(BuildContext context) {
    final cards = [
      _ExploreCard(
        title: 'My Observations',
        subtitle: 'Review your saved finds',
        icon: Icons.collections_bookmark_rounded,
        trailingBadge: observationCount == null ? null : '$observationCount',
        onTap: onTapObservations,
      ),
      _ExploreCard(
        title: 'Species Library',
        subtitle: 'Australia-wide field guide',
        icon: Icons.menu_book_rounded,
        onTap: onTapLibrary,
      ),
      _ExploreCard(
        title: 'Observation Map',
        subtitle: 'View mapped finds',
        icon: Icons.location_on_rounded,
        onTap: onTapMap,
      ),
      _ExploreCard(
        title: 'Field Notes',
        subtitle: 'Local notes and photos',
        icon: Icons.edit_note_rounded,
        onTap: onTapNotes,
      ),
    ];

    if (!twoColumns) {
      return Column(
        children: [
          for (final card in cards) ...[
            card,
            if (card != cards.last) const SizedBox(height: 12),
          ],
        ],
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 3.45,
      children: cards,
    );
  }
}

class _ExploreCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String? trailingBadge;
  final VoidCallback onTap;

  const _ExploreCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.trailingBadge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        height: 76,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0xFF2F8A59),
              Color(0xFF1F6F47),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33245D3F),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xDFFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailingBadge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minWidth: 30),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      trailingBadge!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: _HomeColors.primary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeColors {
  static const background = Color(0xFFF7F4EA);
  static const primary = Color(0xFF2D774E);
  static const buttonGreen = Color(0xFF17824F);
  static const accent = Color(0xFF65A878);
  static const text = Color(0xFF143427);
  static const mutedText = Color(0xFF5F746A);
}
