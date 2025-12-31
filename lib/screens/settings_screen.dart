import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../repositories/observation_repository.dart';
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

  AppSettings? _settings;
  bool _loading = true;
  int? _modelSizeBytes;
  int? _storageBytes;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    final modelSize = await _loadModelSize();
    final storageSize = await _loadStorageUsage();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _modelSizeBytes = modelSize;
      _storageBytes = storageSize;
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

  void _openDisclaimer() {
    Navigator.of(context).pushNamed('/disclaimer');
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
                  const Text(
                    'Detection preferences',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
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
                  const SizedBox(height: 12),
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
                  const Text(
                    'Model info',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Model version',
                    value: 'v1.0 (YOLO11n)',
                  ),
                  _InfoRow(
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
                  const Text(
                    'Storage',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Local usage (approx.)',
                    value: _storageBytes == null
                        ? 'Unknown'
                        : _formatBytes(_storageBytes!),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Safety & Disclaimer',
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
                  const SizedBox(height: 12),
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
