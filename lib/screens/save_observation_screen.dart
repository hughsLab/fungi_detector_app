import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../services/location_capture_service.dart';
import '../services/settings_service.dart';
import '../widgets/forest_background.dart';

class SaveObservationScreen extends StatefulWidget {
  const SaveObservationScreen({super.key});

  @override
  State<SaveObservationScreen> createState() => _SaveObservationScreenState();
}

class _SaveObservationScreenState extends State<SaveObservationScreen> {
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;
  final ObservationRepository _observationRepository =
      ObservationRepository.instance;
  final SettingsService _settingsService = SettingsService.instance;
  final LocationCaptureService _locationCaptureService =
      LocationCaptureService.instance;
  final Uuid _uuid = const Uuid();

  final TextEditingController _notesController = TextEditingController();

  List<Species> _species = [];
  Species? _selectedSpecies;
  bool _includeConfidence = false;
  double _confidenceValue = 0.6;
  bool _locationEnabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    final args =
        ModalRoute.of(context)?.settings.arguments as SaveObservationArgs?;
    _loadData(args);
  }

  Future<void> _loadData(SaveObservationArgs? args) async {
    final species = await _speciesRepository.loadSpecies();
    final settings = await _settingsService.loadSettings();
    if (!mounted) return;

    Species? preselected;
    if (args?.preselectedSpeciesId != null) {
      preselected = species
          .where((item) => item.id == args!.preselectedSpeciesId)
          .firstOrNull;
    }

    setState(() {
      _species = species;
      _selectedSpecies =
          preselected ?? (species.isNotEmpty ? species.first : null);
      _confidenceValue = settings.confidenceThreshold;
      _locationEnabled = settings.locationTaggingEnabled;
      _loading = false;
    });
  }

  void _saveObservation() async {
    if (_saving) return;
    final species = _selectedSpecies;
    if (species == null) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      CapturedLocation? capturedLocation;
      String? locationMessage;
      ObservationLocationSource locationSource = ObservationLocationSource.none;
      double? latitude;
      double? longitude;
      double? accuracyMeters;
      DateTime? capturedAt;
      if (_locationEnabled) {
        capturedLocation =
            await _locationCaptureService.captureForObservation();
        locationMessage = _locationCaptureService.lastErrorMessage;
        if (capturedLocation != null) {
          latitude = capturedLocation.latitude;
          longitude = capturedLocation.longitude;
          accuracyMeters = capturedLocation.accuracyMeters;
          capturedAt = capturedLocation.capturedAt;
          locationSource = ObservationLocationSource.deviceGps;
        }
      }

      final observation = Observation(
        id: _uuid.v4(),
        speciesId: species.id,
        classIndex: int.tryParse(species.id),
        label: species.commonName?.isNotEmpty == true
            ? species.commonName!
            : species.scientificName,
        confidence: _includeConfidence ? _confidenceValue : null,
        createdAt: DateTime.now(),
        photoPath: null,
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: accuracyMeters,
        capturedAt: capturedAt,
        locationSource: locationSource,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      await _observationRepository.saveObservation(observation);
      if (!mounted) return;
      final String message =
          (locationSource == ObservationLocationSource.deviceGps)
              ? 'Saved (pin added to Map).'
              : (_locationEnabled
                  ? (locationMessage ?? 'Saved without location.')
                  : 'Saved (location tagging off).');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save observation: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _saving = false;
      });
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Save Observation'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ForestBackground(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        includeTopSafeArea: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Record an offline observation',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Species>(
                      value: _selectedSpecies,
                      items: _species
                          .map(
                            (species) => DropdownMenuItem(
                              value: species,
                              child: Text(
                                species.displayName,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedSpecies = value;
                        });
                      },
                      dropdownColor: const Color(0xFF1F4E3D),
                      decoration: InputDecoration(
                        labelText: 'Species',
                        labelStyle: const TextStyle(color: accentTextColor),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _includeConfidence,
                      onChanged: (value) {
                        setState(() {
                          _includeConfidence = value;
                        });
                      },
                      title: const Text(
                        'Include confidence',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Optional manual confidence score',
                        style: TextStyle(color: accentTextColor),
                      ),
                      activeColor: const Color(0xFF8FBFA1),
                    ),
                    if (_includeConfidence)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Confidence: ${(_confidenceValue * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(color: accentTextColor),
                          ),
                          Slider(
                            value: _confidenceValue,
                            min: 0,
                            max: 1,
                            divisions: 20,
                            activeColor: const Color(0xFF8FBFA1),
                            inactiveColor: Colors.white24,
                            onChanged: (value) {
                              setState(() {
                                _confidenceValue = value;
                              });
                            },
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    if (_locationEnabled) ...[
                      const Text(
                        'Location tagging is enabled.',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
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
                          'GPS will be captured when you save. First fix may take a few seconds offline.',
                          style: TextStyle(color: accentTextColor),
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Location tagging is disabled in Settings.',
                          style: TextStyle(color: accentTextColor),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Notes (optional)',
                        labelStyle: const TextStyle(color: accentTextColor),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _saveObservation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8FBFA1),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          _saving ? 'Saving...' : 'Save Observation',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
