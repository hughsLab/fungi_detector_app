import 'package:flutter/material.dart';

import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
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

  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  List<Species> _species = [];
  Species? _selectedSpecies;
  bool _includeConfidence = false;
  double _confidenceValue = 0.6;
  bool _locationEnabled = false;
  bool _loading = true;
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
    final species = _selectedSpecies;
    if (species == null) {
      return;
    }

    ObservationLocation? location;
    if (_locationEnabled) {
      final lat = double.tryParse(_latitudeController.text.trim());
      final lon = double.tryParse(_longitudeController.text.trim());
      if (lat != null && lon != null) {
        location = ObservationLocation(latitude: lat, longitude: lon);
      }
    }

    final observation = Observation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      speciesId: species.id,
      classIndex: int.tryParse(species.id),
      label: species.commonName?.isNotEmpty == true
          ? species.commonName!
          : species.scientificName,
      confidence: _includeConfidence ? _confidenceValue : null,
      timestamp: DateTime.now(),
      photoPath: null,
      location: location,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    await _observationRepository.addObservation(observation);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Observation saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
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
                        'Location (optional)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _latitudeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Latitude',
                          labelStyle: const TextStyle(color: accentTextColor),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _longitudeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Longitude',
                          labelStyle: const TextStyle(color: accentTextColor),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
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
                        onPressed: _saveObservation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8FBFA1),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'Save Observation',
                          style: TextStyle(
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
