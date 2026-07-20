import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/mushroom_id_result.dart';
import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../services/mushroom_id_observation_mapper.dart';
import '../services/settings_service.dart';
import '../widgets/forest_background.dart';
import '../widgets/local_image_preview.dart';

class OnlineIdentificationResultScreen extends StatefulWidget {
  const OnlineIdentificationResultScreen({super.key});

  @override
  State<OnlineIdentificationResultScreen> createState() =>
      _OnlineIdentificationResultScreenState();
}

class _OnlineIdentificationResultScreenState
    extends State<OnlineIdentificationResultScreen> {
  final ObservationRepository _observationRepository =
      ObservationRepository.instance;
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;
  final SettingsService _settingsService = SettingsService.instance;
  final MushroomIdObservationMapper _mapper =
      const MushroomIdObservationMapper();
  final Uuid _uuid = const Uuid();

  OnlineIdentificationResultArgs? _args;
  bool _saving = false;
  bool _saved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _args ??= ModalRoute.of(context)?.settings.arguments
        as OnlineIdentificationResultArgs?;
  }

  Future<void> _saveObservation(OnlineIdentificationResultArgs args) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = args.result;
      final top = result.topSuggestion;
      final draft = _mapper.draftFromResult(result);
      final matchedSpecies = await _speciesRepository.matchSpecies(
        scientificName: draft.scientificName,
        label: draft.label,
      );
      final settings = await _settingsService.loadSettings();
      final photoPath = await _persistPhoto(args.photoPath);
      if (photoPath == null) {
        throw StateError('The selected photo is no longer available.');
      }
      final secondary = result.alternatives.isEmpty
          ? null
          : result.alternatives.first;

      final observation = Observation(
        id: _uuid.v4(),
        speciesId: matchedSpecies?.id ?? draft.scientificName,
        classIndex: null,
        label: draft.label,
        scientificName: draft.scientificName,
        commonName: draft.commonName,
        colloquialName: draft.commonName,
        confidence: draft.confidence,
        rawConfidence: draft.confidence,
        calibratedConfidence: draft.confidence,
        finalScore: draft.confidence,
        top2Label: secondary?.scientificName,
        top2Confidence: secondary?.probability,
        candidates: draft.candidates,
        createdAt: DateTime.now(),
        photoPath: photoPath,
        latitude: args.latitude,
        longitude: args.longitude,
        accuracyMeters: args.accuracyMeters,
        capturedAt: args.capturedAt,
        locationSource: args.latitude != null && args.longitude != null
            ? ObservationLocationSource.deviceGps
            : ObservationLocationSource.none,
        locationLabel: args.locationLabel,
        country: args.country,
        region: args.region,
        notes: draft.notes,
        detectionSource: 'online_mushroom_id',
        identificationSource: 'online_mushroom_id',
        onlineIdentification: true,
        onlineProvider: 'mushroom.id',
        onlineScientificName: top?.scientificName,
        onlineCommonNames: top?.commonNames ?? const <String>[],
        onlineConfidence: top?.probability,
        onlineConfidencePercent: top?.confidencePercent,
        onlineEdibility: top?.edibility,
        onlineToxicity: top?.toxicity,
        onlineDescription: top?.description,
        onlineUrl: top?.url,
        onlineTaxonomy:
            top == null ? null : <String, dynamic>{...top.taxonomy},
        onlineAlternatives:
            result.alternatives.map((item) => item.toCompactJson()).toList(),
        onlineSimilarImages:
            top?.similarImages.map((item) => item.toJson()).toList() ??
                const <Map<String, dynamic>>[],
        identificationWarnings: <String>[
          MushroomIdObservationMapper.safetyWarning,
          ...result.warnings,
        ],
        regionSupported: result.regionSupported,
        locationFilterApplied: result.locationFilterApplied,
        isPublic: settings.shareObservationsOnPublicMap,
      );

      if (kDebugMode) {
        debugPrint(
          'ONLINE_OBSERVATION_SAVE: save tapped id=${observation.id} '
          'detectionSource=${observation.detectionSource} '
          'identificationSource=${observation.identificationSource} '
          'hasLocation=${observation.location != null} '
          'isPublic=${observation.isPublic}',
        );
      }
      await _observationRepository.saveObservation(observation);
      if (!mounted) return;
      _saved = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved online identification.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save observation: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<String?> _persistPhoto(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      return null;
    }
    final directory = await getApplicationSupportDirectory();
    final photosDir = Directory('${directory.path}/observation_photos');
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    final fileName =
        'online_observation_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedPath = '${photosDir.path}${Platform.pathSeparator}$fileName';
    final saved = await source.copy(savedPath);
    return saved.path;
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;
    if (args == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1F4E3D),
        body: Center(
          child: Text(
            'No online identification result available.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final result = args.result;
    final top = result.topSuggestion;
    final bool lowConfidence = !result.hasConfidentTopSuggestion;
    final bool poisonous = _containsPoisonWarning(top);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Identification'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ForestBackground(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        includeTopSafeArea: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResultCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: LocalImagePreview(
                          path: args.photoPath,
                          cacheWidth: 960,
                          placeholder: const ColoredBox(
                            color: Color(0x14000000),
                            child: Center(
                              child: Icon(
                                Icons.image_not_supported,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (lowConfidence)
                      const _WarningBanner(
                        text:
                            'Online identification could not confidently identify this fungus.',
                      ),
                    if (poisonous)
                      const _WarningBanner(text: 'Poisonous warning returned.'),
                    const _WarningBanner(
                      text:
                          'Not for consumption. Do not eat fungi based on app identification.',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      top?.scientificName ?? 'Unknown fungus',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      top == null
                          ? 'No top suggestion returned.'
                          : '${top.confidencePercent.toStringAsFixed(1)}% confidence',
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 14,
                      ),
                    ),
                    if (top?.commonNames.isNotEmpty == true)
                      _InfoLine(
                        label: 'Common Names',
                        value: top!.commonNames.join(', '),
                      ),
                    if ((top?.edibility ?? '').trim().isNotEmpty)
                      _InfoLine(label: 'Edibility', value: top!.edibility!),
                    if ((top?.toxicity ?? '').trim().isNotEmpty)
                      _InfoLine(label: 'Toxicity', value: top!.toxicity!),
                    if ((top?.description ?? '').trim().isNotEmpty)
                      _InfoLine(label: 'Description', value: top!.description!),
                  ],
                ),
              ),
              if (result.alternatives.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ResultCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Secondary possible matches',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...result.alternatives.map(_AlternativeTile.new),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving || _saved
                      ? null
                      : () => _saveObservation(args),
                  icon: const Icon(Icons.bookmark_add),
                  label: Text(_saving ? 'Saving...' : 'Create Observation'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8FBFA1),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Back to detection'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _containsPoisonWarning(MushroomIdSuggestion? suggestion) {
    final text = [
      suggestion?.edibility,
      suggestion?.toxicity,
    ].whereType<String>().join(' ').toLowerCase();
    return text.contains('poison') || text.contains('toxic');
  }
}

class _AlternativeTile extends StatelessWidget {
  final MushroomIdSuggestion suggestion;

  const _AlternativeTile(this.suggestion);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              suggestion.scientificName,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
            ),
          ),
          Text(
            '${suggestion.confidencePercent.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String text;

  const _WarningBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC857).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFC857).withValues(alpha: 0.65),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFFFE8A3),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Widget child;

  const _ResultCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF8FBFA1).withValues(alpha: 0.85),
        ),
      ),
      child: child,
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE7F3E7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
