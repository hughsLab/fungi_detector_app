import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/mushroom_id_result.dart';
import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/toxicity_level.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../services/mushroom_id_observation_mapper.dart';
import '../services/settings_service.dart';
import '../services/species_enrichment_service.dart';
import '../widgets/forest_background.dart';
import '../widgets/local_image_preview.dart';
import '../widgets/toxicity_badge.dart';

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
  final SpeciesEnrichmentService _enrichmentService =
      SpeciesEnrichmentService.instance;

  OnlineIdentificationResultArgs? _args;
  bool _saving = false;
  bool _saved = false;
  bool _enriching = false;
  SpeciesEnrichmentResult? _enrichment;
  Future<SpeciesEnrichmentResult>? _enrichmentFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args == null) {
      _args = ModalRoute.of(context)?.settings.arguments
          as OnlineIdentificationResultArgs?;
      final scientificName = _args?.result.topSuggestion?.scientificName.trim();
      if (scientificName != null && scientificName.isNotEmpty) {
        unawaited(_enrich(scientificName));
      }
    }
  }

  Future<void> _enrich(String scientificName) async {
    setState(() => _enriching = true);
    final future = _enrichmentService.enrich(scientificName);
    _enrichmentFuture = future;
    final result = await future;
    if (!mounted) return;
    setState(() {
      _enrichment = result;
      _enriching = false;
    });
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
      final enrichment = _enrichment;
      final localSpecies = enrichment?.localSpecies ?? matchedSpecies;
      final taxon = enrichment?.iNaturalist;
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
        speciesId: localSpecies?.id ?? draft.scientificName,
        classIndex: null,
        label: localSpecies?.commonName ??
            taxon?.preferredCommonName ??
            draft.label,
        scientificName:
            taxon?.acceptedScientificName ?? draft.scientificName,
        commonName: localSpecies?.commonName ??
            taxon?.preferredCommonName ??
            draft.commonName,
        colloquialName: localSpecies?.colloquialName ??
            localSpecies?.commonName ??
            taxon?.preferredCommonName ??
            draft.commonName,
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
        toxicityLevel:
            enrichment?.toxicityLevel ??
            localSpecies?.toxicityLevel ??
            ToxicityLevel.unknown,
        toxicitySummary:
            enrichment?.toxicitySummary ?? localSpecies?.toxicitySummary,
        toxicitySource:
            enrichment?.toxicitySource ?? localSpecies?.toxicitySource,
        toxicitySourceUrl:
            enrichment?.toxicitySourceUrl ?? localSpecies?.toxicitySourceUrl,
        toxicityVerifiedAt: localSpecies?.toxicityVerifiedAt,
        iNaturalistTaxonId: taxon?.taxonId,
        iNaturalistAcceptedName: taxon?.acceptedScientificName,
        iNaturalistCommonName: taxon?.preferredCommonName,
        iNaturalistPhotoUrl: taxon?.photoUrl,
        iNaturalistPhotoAttribution: taxon?.photoAttribution,
        iNaturalistPhotoLicense: taxon?.photoLicense,
        iNaturalistTaxonUrl: taxon?.taxonUrl,
        iNaturalistGlobalObservationCount: taxon?.globalObservationCount,
        iNaturalistRegionalObservationCount: taxon?.regionalObservationCount,
        iNaturalistObservationCountUpdatedAt: taxon?.fetchedAt,
        conservationStatus: taxon?.conservationStatus,
        conservationStatusAuthority: taxon?.conservationStatusAuthority,
        conservationStatusPlace: taxon?.conservationStatusPlace,
        iNaturalistDataUpdatedAt: taxon?.fetchedAt,
        iNaturalistMatchStatus: taxon?.status,
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
      final deferred = _enrichmentFuture;
      if (enrichment == null && deferred != null) {
        unawaited(_saveDeferredEnrichment(observation, deferred));
      }
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

  Future<void> _saveDeferredEnrichment(
    Observation observation,
    Future<SpeciesEnrichmentResult> future,
  ) async {
    try {
      final enrichment = await future;
      final taxon = enrichment.iNaturalist;
      final local = enrichment.localSpecies;
      final enriched = observation.copyWith(
        speciesId: local?.id,
        label: local?.commonName ?? taxon.preferredCommonName,
        scientificName: taxon.acceptedScientificName,
        commonName: local?.commonName ?? taxon.preferredCommonName,
        colloquialName:
            local?.colloquialName ??
            local?.commonName ??
            taxon.preferredCommonName,
        toxicityLevel: enrichment.toxicityLevel,
        toxicitySummary: enrichment.toxicitySummary,
        toxicitySource: enrichment.toxicitySource,
        toxicitySourceUrl: enrichment.toxicitySourceUrl,
        toxicityVerifiedAt: local?.toxicityVerifiedAt,
        iNaturalistTaxonId: taxon.taxonId,
        iNaturalistAcceptedName: taxon.acceptedScientificName,
        iNaturalistCommonName: taxon.preferredCommonName,
        iNaturalistPhotoUrl: taxon.photoUrl,
        iNaturalistPhotoAttribution: taxon.photoAttribution,
        iNaturalistPhotoLicense: taxon.photoLicense,
        iNaturalistTaxonUrl: taxon.taxonUrl,
        iNaturalistGlobalObservationCount: taxon.globalObservationCount,
        iNaturalistRegionalObservationCount: taxon.regionalObservationCount,
        iNaturalistObservationCountUpdatedAt: taxon.fetchedAt,
        conservationStatus: taxon.conservationStatus,
        conservationStatusAuthority: taxon.conservationStatusAuthority,
        conservationStatusPlace: taxon.conservationStatusPlace,
        iNaturalistDataUpdatedAt: taxon.fetchedAt,
        iNaturalistMatchStatus: taxon.status,
      );
      await _observationRepository.saveObservation(enriched);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Deferred iNaturalist enrichment was not saved: $error');
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
    final enrichment = _enrichment;

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
                    const SizedBox(height: 10),
                    ToxicityBadge(
                      level:
                          enrichment?.toxicityLevel ?? ToxicityLevel.unknown,
                    ),
                    if (_enriching)
                      const _InfoLine(
                        label: 'Species information',
                        value: 'Checking iNaturalist…',
                      )
                    else if (enrichment?.iNaturalist.status.name == 'matched') ...[
                      const _InfoLine(
                        label: 'Identification source',
                        value: 'Online identification',
                      ),
                      const _InfoLine(
                        label: 'Species information',
                        value: 'iNaturalist',
                      ),
                      if (enrichment?.iNaturalist.globalObservationCount != null)
                        _InfoLine(
                          label: 'iNaturalist public observations',
                          value: enrichment!
                              .iNaturalist.globalObservationCount!
                              .toString(),
                        ),
                    ] else
                      const _InfoLine(
                        label: 'Toxicity',
                        value:
                            'Toxicity information unavailable for this species',
                      ),
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
