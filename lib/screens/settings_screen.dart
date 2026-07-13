import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../repositories/observation_repository.dart';
import '../repositories/user_profile_repository.dart';
import '../services/map_tile_cache_service.dart';
import '../services/settings_service.dart';
import '../widgets/forest_background.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService.instance;
  final ObservationRepository _observationRepository =
      ObservationRepository.instance;
  final UserProfileRepository _userProfileRepository =
      UserProfileRepository.instance;
  final MapTileCacheService _mapTileCacheService = MapTileCacheService.instance;

  AppSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    await _mapTileCacheService.ensureInitialized(
      cacheSoftLimitMb: settings.mapTileCacheMaxSizeMb,
      maxDatabaseSizeKiB: settings.mapTileCacheMaxSizeMb * 1024,
    );
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _updateSettings(AppSettings settings) async {
    await _settingsService.updateSettings(settings);
    if (!mounted) return;
    setState(() {
      _settings = settings;
    });
  }

  Future<void> _clearLocalData() async {
    await _observationRepository.clearObservations();
    await _settingsService.setDisclaimerAcknowledged(false);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Local data cleared.')));
  }

  Future<void> _clearMapCache() async {
    await _mapTileCacheService.clearCache();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Offline maps cleared.')));
  }

  Future<void> _updateMapCacheLimit(int limitMb) async {
    final current = _settings;
    if (current == null) {
      return;
    }
    final updated = current.copyWith(mapTileCacheMaxSizeMb: limitMb);
    await _updateSettings(updated);
    await _mapTileCacheService.configureCacheLimitMb(limitMb);
  }

  void _openAbout() {
    Navigator.of(context).pushNamed('/about');
  }

  void _openUsernameEditor() {
    Navigator.of(context).pushNamed('/choose-username');
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ForestBackground(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        includeTopSafeArea: false,
        child: _loading || _settings == null
            ? const Center(child: CircularProgressIndicator())
              : ListView(
                children: [
                  const _SectionHeader(title: 'Account'),
                  const SizedBox(height: 8),
                  StreamBuilder<UserProfile?>(
                    stream: _userProfileRepository.streamCurrentUserProfile(),
                    builder: (context, snapshot) {
                      final profile = snapshot.data;
                      final username = profile?.username?.trim();
                      final hasUsername =
                          username != null && username.isNotEmpty;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          hasUsername ? username : 'Choose username',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: const Text(
                          'Your username may appear beside public observations.',
                          style: TextStyle(color: accentTextColor),
                        ),
                        trailing: const Icon(
                          Icons.edit,
                          color: Colors.white70,
                        ),
                        onTap: _openUsernameEditor,
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeader(title: 'Detection'),
                  const SizedBox(height: 12),
                  const Text(
                    'Camera speed / accuracy',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _settings!.cameraPerformancePreset,
                    dropdownColor: const Color(0xFF1F4E3D),
                    items: const [
                      DropdownMenuItem(
                        value: 'Low',
                        child: Text(
                          'Fast',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Medium',
                        child: Text(
                          'Balanced',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'High',
                        child: Text(
                          'Accurate',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _updateSettings(
                        _settings!.copyWith(cameraPerformancePreset: value),
                      );
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeader(title: 'Location & Privacy'),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _settings!.shareObservationsOnPublicMap,
                    onChanged: (value) {
                      _updateSettings(
                        _settings!.copyWith(
                          shareObservationsOnPublicMap: value,
                        ),
                      );
                    },
                    title: const Text(
                      'Share observations on public map',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'When enabled, saved cloud observations can appear as public map pins. Other users can view them but cannot edit or delete them.',
                      style: TextStyle(color: accentTextColor),
                    ),
                    activeColor: const Color(0xFF8FBFA1),
                  ),
                  StreamBuilder<UserProfile?>(
                    stream: _userProfileRepository.streamCurrentUserProfile(),
                    builder: (context, snapshot) {
                      final username = snapshot.data?.username?.trim();
                      final hasUsername =
                          username != null && username.isNotEmpty;
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: hasUsername &&
                            _settings!.showUsernameOnPublicObservations,
                        onChanged: !hasUsername
                            ? null
                            : (value) {
                                _updateSettings(
                                  _settings!.copyWith(
                                    showUsernameOnPublicObservations: value,
                                  ),
                                );
                              },
                        title: const Text(
                          'Show username on public observations',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          hasUsername
                              ? 'Show your username with public map observations.'
                              : 'Choose a username before this can be enabled.',
                          style: const TextStyle(color: accentTextColor),
                        ),
                        activeColor: const Color(0xFF8FBFA1),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _settings!.locationTaggingEnabled,
                    onChanged: (value) {
                      _updateSettings(
                        _settings!.copyWith(locationTaggingEnabled: value),
                      );
                    },
                    title: const Text(
                      'Save location with observations',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Adds an approximate location to saved fungi records.',
                      style: TextStyle(color: accentTextColor),
                    ),
                    activeColor: const Color(0xFF8FBFA1),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Location label',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<LocationLabelMode>(
                    value: _settings!.locationLabelMode,
                    dropdownColor: const Color(0xFF1F4E3D),
                    items: const [
                      DropdownMenuItem(
                        value: LocationLabelMode.locality,
                        child: Text(
                          'Nearby locality',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      DropdownMenuItem(
                        value: LocationLabelMode.coordinates,
                        child: Text(
                          'Coordinates only',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _updateSettings(
                        _settings!.copyWith(locationLabelMode: value),
                      );
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeader(title: 'Offline Maps'),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _settings!.mapTileCachingEnabled,
                    onChanged: (value) {
                      _updateSettings(
                        _settings!.copyWith(mapTileCachingEnabled: value),
                      );
                    },
                    title: const Text(
                      'Save map areas for offline use',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Stores viewed map areas for offline use.',
                      style: TextStyle(color: accentTextColor),
                    ),
                    activeColor: const Color(0xFF8FBFA1),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Offline map storage limit',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    value: _settings!.mapTileCacheMaxSizeMb,
                    dropdownColor: const Color(0xFF1F4E3D),
                    items: const [
                      DropdownMenuItem(
                        value: 250,
                        child: Text(
                          '250 MB',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 500,
                        child: Text(
                          '500 MB',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _updateMapCacheLimit(value);
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _clearMapCache,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Clear offline maps'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Tiles are cached while browsing and can also be downloaded in the map screen for offline use.',
                      style: TextStyle(color: accentTextColor, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeader(title: 'Saved Data'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Observations and field notes are stored on this device.',
                      style: TextStyle(color: accentTextColor, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _clearLocalData,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Clear local data'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeader(title: 'About'),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'About',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Credits and model info',
                      style: TextStyle(color: accentTextColor),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.white70,
                    ),
                    onTap: _openAbout,
                  ),
                ],
              ),
      ),
    );
  }

}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
  }
}
