import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppSettings {
  final double confidenceThreshold;
  final bool locationTaggingEnabled;
  final String cameraPerformancePreset;
  final bool disclaimerAcknowledged;

  const AppSettings({
    required this.confidenceThreshold,
    required this.locationTaggingEnabled,
    required this.cameraPerformancePreset,
    required this.disclaimerAcknowledged,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      confidenceThreshold: 0.6,
      locationTaggingEnabled: false,
      cameraPerformancePreset: 'Medium',
      disclaimerAcknowledged: false,
    );
  }

  AppSettings copyWith({
    double? confidenceThreshold,
    bool? locationTaggingEnabled,
    String? cameraPerformancePreset,
    bool? disclaimerAcknowledged,
  }) {
    return AppSettings(
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      locationTaggingEnabled:
          locationTaggingEnabled ?? this.locationTaggingEnabled,
      cameraPerformancePreset:
          cameraPerformancePreset ?? this.cameraPerformancePreset,
      disclaimerAcknowledged:
          disclaimerAcknowledged ?? this.disclaimerAcknowledged,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      confidenceThreshold:
          (json['confidenceThreshold'] as num?)?.toDouble() ??
              AppSettings.defaults().confidenceThreshold,
      locationTaggingEnabled:
          json['locationTaggingEnabled'] as bool? ?? false,
      cameraPerformancePreset:
          json['cameraPerformancePreset']?.toString() ?? 'Medium',
      disclaimerAcknowledged:
          json['disclaimerAcknowledged'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'confidenceThreshold': confidenceThreshold,
      'locationTaggingEnabled': locationTaggingEnabled,
      'cameraPerformancePreset': cameraPerformancePreset,
      'disclaimerAcknowledged': disclaimerAcknowledged,
    };
  }
}

class SettingsService {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  Future<File> _getFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/settings.json');
  }

  Future<AppSettings> loadSettings() async {
    final file = await _getFile();
    if (!await file.exists()) {
      return AppSettings.defaults();
    }
    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return AppSettings.fromJson(data);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    final file = await _getFile();
    await file.writeAsString(jsonEncode(settings.toJson()));
  }

  Future<AppSettings> updateSettings(AppSettings settings) async {
    await saveSettings(settings);
    return settings;
  }

  Future<AppSettings> setDisclaimerAcknowledged(bool value) async {
    final current = await loadSettings();
    final updated = current.copyWith(disclaimerAcknowledged: value);
    await saveSettings(updated);
    return updated;
  }

  Future<AppSettings> resetSettings() async {
    final defaults = AppSettings.defaults();
    await saveSettings(defaults);
    return defaults;
  }
}
