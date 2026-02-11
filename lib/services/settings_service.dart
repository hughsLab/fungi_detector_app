import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings {
  final double confidenceThreshold;
  final bool locationTaggingEnabled;
  final String cameraPerformancePreset;
  final bool disclaimerAcknowledged;
  final bool mapTileCachingEnabled;

  const AppSettings({
    required this.confidenceThreshold,
    required this.locationTaggingEnabled,
    required this.cameraPerformancePreset,
    required this.disclaimerAcknowledged,
    required this.mapTileCachingEnabled,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      confidenceThreshold: 0.6,
      locationTaggingEnabled: false,
      cameraPerformancePreset: 'Medium',
      disclaimerAcknowledged: false,
      mapTileCachingEnabled: true,
    );
  }

  AppSettings copyWith({
    double? confidenceThreshold,
    bool? locationTaggingEnabled,
    String? cameraPerformancePreset,
    bool? disclaimerAcknowledged,
    bool? mapTileCachingEnabled,
  }) {
    return AppSettings(
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      locationTaggingEnabled:
          locationTaggingEnabled ?? this.locationTaggingEnabled,
      cameraPerformancePreset:
          cameraPerformancePreset ?? this.cameraPerformancePreset,
      disclaimerAcknowledged:
          disclaimerAcknowledged ?? this.disclaimerAcknowledged,
      mapTileCachingEnabled:
          mapTileCachingEnabled ?? this.mapTileCachingEnabled,
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
      mapTileCachingEnabled:
          json['mapTileCachingEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'confidenceThreshold': confidenceThreshold,
      'locationTaggingEnabled': locationTaggingEnabled,
      'cameraPerformancePreset': cameraPerformancePreset,
      'disclaimerAcknowledged': disclaimerAcknowledged,
      'mapTileCachingEnabled': mapTileCachingEnabled,
    };
  }
}

class SettingsService {
  SettingsService._();

  static final SettingsService instance = SettingsService._();
  final ValueNotifier<AppSettings> settingsNotifier =
      ValueNotifier<AppSettings>(AppSettings.defaults());

  Future<File> _getFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/settings.json');
  }

  Future<AppSettings> loadSettings() async {
    final file = await _getFile();
    if (!await file.exists()) {
      final defaults = AppSettings.defaults();
      settingsNotifier.value = defaults;
      return defaults;
    }
    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final settings = AppSettings.fromJson(data);
      settingsNotifier.value = settings;
      return settings;
    } catch (_) {
      final defaults = AppSettings.defaults();
      settingsNotifier.value = defaults;
      return defaults;
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    final file = await _getFile();
    await file.writeAsString(jsonEncode(settings.toJson()));
  }

  Future<AppSettings> updateSettings(AppSettings settings) async {
    await saveSettings(settings);
    settingsNotifier.value = settings;
    return settings;
  }

  Future<AppSettings> setDisclaimerAcknowledged(bool value) async {
    final current = await loadSettings();
    final updated = current.copyWith(disclaimerAcknowledged: value);
    await saveSettings(updated);
    settingsNotifier.value = updated;
    return updated;
  }

  Future<AppSettings> resetSettings() async {
    final defaults = AppSettings.defaults();
    await saveSettings(defaults);
    settingsNotifier.value = defaults;
    return defaults;
  }
}
