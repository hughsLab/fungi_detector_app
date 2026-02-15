import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../repositories/field_notes_repository.dart';
import '../repositories/observation_repository.dart';
import '../services/attachment_storage_service.dart';
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
  final FieldNotesRepository _fieldNotesRepository =
      FieldNotesRepository.instance;
  final AttachmentStorageService _attachmentStorageService =
      AttachmentStorageService.instance;
  final MapTileCacheService _mapTileCacheService =
      MapTileCacheService.instance;

  AppSettings? _settings;
  bool _loading = true;
  int? _modelSizeBytes;
  int? _storageBytes;
  int? _fieldNotesBytes;
  int? _fieldNotesThumbBytes;
  int? _tileCacheBytes;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    final modelSize = await _loadModelSize();
    final storageSize = await _loadStorageUsage();
    final fieldNotesBytes = await _fieldNotesRepository.getStorageBytes();
    final fieldNotesThumbBytes =
        await _attachmentStorageService.getThumbnailCacheBytes();
    await _mapTileCacheService.ensureInitialized();
    final tileCacheSize = await _mapTileCacheService.getCacheSizeBytes();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _modelSizeBytes = modelSize;
      _storageBytes = storageSize;
      _fieldNotesBytes = fieldNotesBytes;
      _fieldNotesThumbBytes = fieldNotesThumbBytes;
      _tileCacheBytes = tileCacheSize;
      _loading = false;
    });
  }

  Future<int?> _loadModelSize() async {
    try {
      final data =
          await rootBundle.load('assets/models/yolo11n_float32.tflite');
      return data.lengthInBytes;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _loadStorageUsage() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/observations.json');
      if (!await file.exists()) {
        return 0;
      }
      return await file.length();
    } catch (_) {
      return null;
    }
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
    final storageSize = await _loadStorageUsage();
    if (!mounted) return;
    setState(() {
      _storageBytes = storageSize;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Local data cleared.')),
    );
  }

  Future<void> _clearMapCache() async {
    await _mapTileCacheService.clearCache();
    final tileCacheSize = await _mapTileCacheService.getCacheSizeBytes();
    if (!mounted) return;
    setState(() {
      _tileCacheBytes = tileCacheSize;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cached map tiles cleared.')),
    );
  }

  Future<void> _clearFieldNoteThumbnails() async {
    await _attachmentStorageService.clearThumbnails();
    final fieldNotesBytes = await _fieldNotesRepository.getStorageBytes();
    final thumbBytes = await _attachmentStorageService.getThumbnailCacheBytes();
    if (!mounted) return;
    setState(() {
      _fieldNotesBytes = fieldNotesBytes;
      _fieldNotesThumbBytes = thumbBytes;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Field note thumbnails cleared.')),
    );
  }

  void _openDisclaimer() {
    Navigator.of(context).pushNamed('/disclaimer');
  }

  void _openAbout() {
    Navigator.of(context).pushNamed('/about');
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
                  const _SectionHeader(title: 'Detection'),
                  const SizedBox(height: 12),
                  Text(
                    'Confidence threshold: ${(_settings!.confidenceThreshold * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: accentTextColor),
                  ),
                  Slider(
                    value: _settings!.confidenceThreshold,
                    min: 0.1,
                    max: 1,
                    divisions: 18,
                    activeColor: const Color(0xFF8FBFA1),
                    inactiveColor: Colors.white24,
                    onChanged: (value) {
                      _updateSettings(
                        _settings!.copyWith(confidenceThreshold: value),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Camera performance preset',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _settings!.cameraPerformancePreset,
                    dropdownColor: const Color(0xFF1F4E3D),
                    items: const [
                      DropdownMenuItem(
                        value: 'Low',
                        child: Text('Low', style: TextStyle(color: Colors.white)),
                      ),
                      DropdownMenuItem(
                        value: 'Medium',
                        child:
                            Text('Medium', style: TextStyle(color: Colors.white)),
                      ),
                      DropdownMenuItem(
                        value: 'High',
                        child: Text('High', style: TextStyle(color: Colors.white)),
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
                  const _SectionHeader(title: 'Privacy'),
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
                      'Location tagging',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Store coarse lat/lon with observations',
                      style: TextStyle(color: accentTextColor),
                    ),
                    activeColor: const Color(0xFF8FBFA1),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Location label mode',
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
                          'Locality name (offline dataset)',
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
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Local usage (approx.)',
                    value: _storageBytes == null
                        ? 'Unknown'
                        : _formatBytes(_storageBytes!),
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
                  const _SectionHeader(title: 'Map'),
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
                      'Map tile caching',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Cache tiles you view for offline use',
                      style: TextStyle(color: accentTextColor),
                    ),
                    activeColor: const Color(0xFF8FBFA1),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Map tile cache (approx.)',
                    value: _tileCacheBytes == null
                        ? 'Unknown'
                        : _formatBytes(_tileCacheBytes!),
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
                      child: const Text('Clear cached map tiles'),
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
                      'Tiles are cached as you browse. Bulk downloading is intentionally disabled to respect tile provider terms.',
                      style: TextStyle(color: accentTextColor, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeader(title: 'Field Notes'),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Field notes storage',
                    value: _fieldNotesBytes == null
                        ? 'Unknown'
                        : _formatBytes(_fieldNotesBytes!),
                  ),
                  _InfoRow(
                    label: 'Thumbnail cache',
                    value: _fieldNotesThumbBytes == null
                        ? 'Unknown'
                        : _formatBytes(_fieldNotesThumbBytes!),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _clearFieldNoteThumbnails,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Clear thumbnails cache'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Export / backup (coming soon)'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeader(title: 'Model Info'),
                  const SizedBox(height: 8),
                  const _InfoRow(
                    label: 'Model',
                    value: 'YOLOv11n custom-trained',
                  ),
                  const _InfoRow(
                    label: 'Species set',
                    value: 'Australia-wide species set',
                  ),
                  const _InfoRow(
                    label: 'Inference',
                    value: 'Offline inference',
                  ),
                  const _InfoRow(
                    label: 'Model file',
                    value: 'yolo11n_float32.tflite',
                  ),
                  _InfoRow(
                    label: 'Model size',
                    value: _modelSizeBytes == null
                        ? 'Unknown'
                        : _formatBytes(_modelSizeBytes!),
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeader(title: 'Safety'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'AI results are probabilistic and must not be used for edibility decisions.',
                      style: TextStyle(color: accentTextColor, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Safety Disclaimer',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Review the required safety notice',
                      style: TextStyle(color: accentTextColor),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.white70,
                    ),
                    onTap: _openDisclaimer,
                  ),
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: accentTextColor)),
          Text(value, style: const TextStyle(color: Colors.white)),
        ],
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
