import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/field_note.dart';
import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../models/species_map_marker.dart';
import '../repositories/field_notes_repository.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../services/location_capture_service.dart';
import '../services/location_label_service.dart';
import '../services/settings_service.dart';
import '../services/species_map_location_resolver.dart';
import '../utils/formatting.dart';
import '../utils/lichen_headline_gate.dart';
import '../widgets/forest_background.dart';
import '../widgets/global_distribution_map_preview.dart';
import '../widgets/key_features_section.dart';
import '../widgets/local_image_preview.dart';

class DetectionResultScreen extends StatefulWidget {
  const DetectionResultScreen({super.key});

  @override
  State<DetectionResultScreen> createState() => _DetectionResultScreenState();
}

class _DetectionResultScreenState extends State<DetectionResultScreen> {
  final ObservationRepository _observationRepository =
      ObservationRepository.instance;
  final FieldNotesRepository _fieldNotesRepository =
      FieldNotesRepository.instance;
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;
  final SettingsService _settingsService = SettingsService.instance;
  final LocationCaptureService _locationCaptureService =
      LocationCaptureService.instance;
  final LocationLabelService _locationLabelService =
      LocationLabelService.instance;
  final Uuid _uuid = const Uuid();
  bool _saving = false;
  bool _saved = false;
  DetectionResultArgs? _args;
  String? _tempPhotoPath;
  Future<Species?>? _speciesFuture;
  bool _ownsTempPhoto = true;
  bool _resultLocked = false;
  int _selectedCandidateIndex = 0;
  String _selectedLabel = '';
  double _selectedConfidence = 0.0;
  int? _selectedClassIndex;
  String? _selectedSpeciesId;
  Species? _matchedSpecies;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) {
      return;
    }
    final args =
        ModalRoute.of(context)?.settings.arguments as DetectionResultArgs?;
    if (args != null) {
      _args = args;
      _tempPhotoPath = args.photoPath;
      _ownsTempPhoto = !args.isSavedView;
      _initializeSelection(args);
      _speciesFuture = _loadMatchedSpecies(args).then((species) {
        if (!mounted) return species;
        if (species != null) {
          setState(() {
            _matchedSpecies = species;
            if (_selectedCandidateIndex == 0 && _selectedSpeciesId == null) {
              _selectedSpeciesId = species.id;
            }
          });
        }
        return species;
      });
    }
  }

  @override
  void dispose() {
    _cleanupTempPhoto();
    super.dispose();
  }

  void _initializeSelection(DetectionResultArgs args) {
    final candidates = _resultCandidates(args);
    final primary = candidates.first;
    _selectedCandidateIndex = 0;
    _selectedLabel = primary.label;
    _selectedConfidence = primary.confidence;
    _selectedClassIndex = primary.classIndex ?? primary.sourceClassId;
    _selectedSpeciesId = primary.speciesId;
    _resultLocked =
        args.isSavedView || !args.isConfirmed || candidates.length < 2;
  }

  void _selectCandidate(int index) {
    final args = _args;
    if (args == null) return;
    if (_resultLocked) return;

    final candidates = _resultCandidates(args);
    if (index < 0 || index >= candidates.length) {
      return;
    }
    final candidate = candidates[index];
    setState(() {
      _selectedCandidateIndex = index;
      _selectedLabel = candidate.label;
      _selectedConfidence = candidate.confidence;
      _selectedClassIndex = candidate.classIndex ?? candidate.sourceClassId;
      _selectedSpeciesId =
          candidate.speciesId ?? (index == 0 ? _matchedSpecies?.id : null);
    });
  }

  List<ObservationCandidate> _resultCandidates(DetectionResultArgs args) {
    final explicit = args.candidates
        .where(_isValidCandidate)
        .take(3)
        .toList(growable: false);
    if (explicit.isNotEmpty) {
      return explicit;
    }
    final fallback = <ObservationCandidate>[
      ObservationCandidate(
        label: args.lockedLabel,
        confidence: args.top1AvgConf,
        classIndex: args.classIndex,
        speciesId: args.speciesId,
        modelId: args.modelId,
        modelDisplayName: args.modelDisplayName,
        sourceClassId: args.sourceClassId,
        rawConfidence: args.rawConfidence,
        calibratedConfidence: args.calibratedConfidence,
        finalScore: args.finalScore,
      ),
    ];
    if (args.top2Label != null &&
        args.top2Label!.trim().isNotEmpty &&
        args.top2AvgConf != null &&
        args.top2AvgConf!.isFinite) {
      fallback.add(
        ObservationCandidate(
          label: args.top2Label!,
          confidence: args.top2AvgConf!,
          classIndex: args.top2ClassIndex,
          modelId: args.top2ModelId,
          modelDisplayName: args.top2ModelDisplayName,
          sourceClassId: args.top2SourceClassId,
          rawConfidence: args.top2AvgConf,
          calibratedConfidence: args.top2AvgConf,
          finalScore: args.top2AvgConf,
        ),
      );
    }
    final validFallback =
        fallback.where(_isValidCandidate).take(3).toList(growable: false);
    return validFallback.isEmpty
        ? fallback.take(1).toList(growable: false)
        : validFallback;
  }

  bool _isValidCandidate(ObservationCandidate candidate) {
    return candidate.label.trim().isNotEmpty &&
        candidate.label.trim() != 'Unknown' &&
        candidate.confidence.isFinite &&
        candidate.confidence >= 0.0;
  }

  void _toggleLock() {
    if (_args?.isSavedView ?? false) return;
    setState(() {
      _resultLocked = !_resultLocked;
    });
  }

  String _candidateTitle(int index) {
    switch (index) {
      case 0:
        return 'Primary Candidate';
      case 1:
        return 'Secondary Candidate';
      case 2:
        return 'Third Candidate';
      default:
        return 'Candidate ${index + 1}';
    }
  }

  Future<void> _saveObservation(DetectionResultArgs args) async {
    if (_saving) return;
    if (!args.isConfirmed) {
      _showMessage('This scan was not confirmed. It cannot be saved as a species.');
      return;
    }

    final label = _selectedLabel.trim();
    if (label.isEmpty || label == 'Unknown') {
      _showMessage('Detection label is unavailable. Cannot save.');
      return;
    }
    final classIndex = _selectedClassIndex;
    if (classIndex == null || classIndex < 0) {
      _showMessage('Detection class index is invalid. Cannot save.');
      return;
    }
    final confidence = _selectedConfidence;
    if (confidence.isNaN || confidence.isInfinite) {
      _showMessage('Detection confidence is invalid. Cannot save.');
      return;
    }
    final sourcePhotoPath = args.photoPath?.trim();
    if (sourcePhotoPath == null || sourcePhotoPath.isEmpty) {
      _showMessage('A photo is required. Run the scan again before saving.');
      return;
    }

    setState(() {
      _saving = true;
    });
    try {
      final photoPath = await _persistPhoto(sourcePhotoPath);
      if (photoPath == null) {
        throw StateError('The captured photo is no longer available.');
      }
      final candidates = _resultCandidates(args);
      final selectedCandidate = candidates[_selectedCandidateIndex];
      final savedCandidates = <ObservationCandidate>[
        selectedCandidate,
        ...candidates.where((candidate) => candidate != selectedCandidate),
      ];
      final ObservationCandidate? secondaryCandidate =
          savedCandidates.length > 1 ? savedCandidates[1] : null;
      final String selectedSpeciesId = await _resolveSelectedSpeciesId(
        args: args,
        candidate: selectedCandidate,
        label: label,
      );
      final settings = await _settingsService.loadSettings();
      CapturedLocation? capturedLocation;
      String? locationMessage;
      ObservationLocationSource locationSource = ObservationLocationSource.none;
      double? latitude;
      double? longitude;
      double? accuracyMeters;
      DateTime? capturedAt;
      String? locationLabel;
      if (settings.locationTaggingEnabled) {
        capturedLocation =
            await _locationCaptureService.captureForObservation();
        locationMessage = _locationCaptureService.lastErrorMessage;
        if (capturedLocation != null) {
          latitude = capturedLocation.latitude;
          longitude = capturedLocation.longitude;
          accuracyMeters = capturedLocation.accuracyMeters;
          capturedAt = capturedLocation.capturedAt;
          locationSource = ObservationLocationSource.deviceGps;
          locationLabel = await _locationLabelService.labelFor(
            latitude: latitude,
            longitude: longitude,
            mode: settings.locationLabelMode,
          );
        }
      }

      final observation = Observation(
        id: _uuid.v4(),
        speciesId: selectedSpeciesId,
        classIndex: classIndex,
        modelId: selectedCandidate.modelId,
        modelDisplayName: selectedCandidate.modelDisplayName,
        sourceClassId: selectedCandidate.sourceClassId,
        label: label,
        scientificName: _matchedSpecies?.scientificName ?? label,
        commonName: _matchedSpecies?.commonName,
        colloquialName: _matchedSpecies?.colloquialName,
        confidence: confidence,
        rawConfidence: selectedCandidate.rawConfidence,
        calibratedConfidence: selectedCandidate.calibratedConfidence,
        finalScore: selectedCandidate.finalScore ?? selectedCandidate.confidence,
        top2Label: secondaryCandidate?.label,
        top2Confidence: secondaryCandidate?.confidence,
        top2ModelId: secondaryCandidate?.modelId,
        top2ModelDisplayName: secondaryCandidate?.modelDisplayName,
        top2SourceClassId: secondaryCandidate?.sourceClassId,
        candidates: savedCandidates,
        top1VoteRatio: args.top1VoteRatio,
        windowFrameCount: args.windowFrameCount,
        windowDurationMs: args.windowDurationMs,
        stabilityWinCount: args.stabilityWinCount,
        stabilityWindowSize: args.stabilityWindowSize,
        isLichen: args.isLichen,
        createdAt: DateTime.now(),
        photoPath: photoPath,
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: accuracyMeters,
        capturedAt: capturedAt,
        locationSource: locationSource,
        locationLabel: locationLabel,
        notes: null,
        detectionSource: 'offline_model',
        identificationSource: 'offline',
        isPublic: settings.shareObservationsOnPublicMap,
      );
      if (kDebugMode) {
        debugPrint(
          'OFFLINE_OBSERVATION_SAVE: save tapped id=${observation.id} '
          'detectionSource=${observation.detectionSource} '
          'identificationSource=${observation.identificationSource} '
          'hasLocation=${observation.location != null} '
          'isPublic=${observation.isPublic}',
        );
      }
      await _observationRepository.saveObservation(observation);
      if (!mounted) return;
      _saved = true;
      final String message =
          (locationSource == ObservationLocationSource.deviceGps)
              ? 'Saved (pin added to Map).'
              : (settings.locationTaggingEnabled
                  ? (locationMessage ?? 'Saved without location.')
                  : 'Saved (location tagging off).');
      _showMessage(message);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to save observation: $e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<Species?> _loadMatchedSpecies(DetectionResultArgs args) async {
    return _speciesRepository.matchSpecies(
      speciesId: args.speciesId,
      modelId: args.modelId,
      sourceClassId: args.sourceClassId ?? args.classIndex,
      scientificName: args.lockedLabel,
      label: args.lockedLabel,
    );
  }

  Future<String> _resolveSelectedSpeciesId({
    required DetectionResultArgs args,
    required ObservationCandidate candidate,
    required String label,
  }) async {
    final explicit = candidate.speciesId?.trim() ?? _selectedSpeciesId?.trim();
    final Species? matched = await _speciesRepository.matchSpecies(
      speciesId: explicit,
      modelId: candidate.modelId,
      sourceClassId: candidate.sourceClassId ?? candidate.classIndex,
      scientificName: label,
      label: label,
    );
    if (matched != null) return matched.id;
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    if (candidate.label == args.lockedLabel && _matchedSpecies != null) {
      return _matchedSpecies!.id;
    }
    return label;
  }

  Future<String?> _persistPhoto(String tempPath) async {
    final tempFile = File(tempPath);
    if (!await tempFile.exists()) {
      return null;
    }
    final directory = await getApplicationSupportDirectory();
    final photosDir = Directory('${directory.path}/observation_photos');
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    final fileName = 'observation_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedPath = '${photosDir.path}${Platform.pathSeparator}$fileName';
    final savedFile = await tempFile.copy(savedPath);
    try {
      await tempFile.delete();
    } catch (_) {}
    return savedFile.path;
  }

  void _cleanupTempPhoto() {
    if (!_ownsTempPhoto) return;
    if (_saved) return;
    final path = _tempPhotoPath;
    if (path == null) return;
    final file = File(path);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }

  void _handleBack() {
    _cleanupTempPhoto();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openObservationOnMap(DetectionResultArgs args) {
    final double? lat = args.latitude;
    final double? lon = args.longitude;
    if (lat == null || lon == null) {
      _showMessage('No location recorded for this observation.');
      return;
    }
    Navigator.of(context).pushNamed(
      '/map',
      arguments: MapFocusRequest(
        observationId: args.observationId,
        lat: lat,
        lon: lon,
        label: args.locationLabel ?? args.lockedLabel,
      ),
    );
  }

  Widget _buildFieldNotesPanel(String observationId) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF8FBFA1).withValues(alpha: 0.85),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Field Notes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    '/field-note-editor',
                    arguments: FieldNoteEditorArgs(
                      prelinkedObservationId: observationId,
                    ),
                  );
                },
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'Add',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          StreamBuilder<List<FieldNote>>(
            stream: _fieldNotesRepository.watchAllNotes(),
            builder: (context, snapshot) {
              final notes = (snapshot.data ?? const <FieldNote>[])
                  .where(
                    (note) =>
                        note.links.observationIds.contains(observationId),
                  )
                  .toList();
              if (notes.isEmpty) {
                return const Text(
                  'No notes linked to this observation yet.',
                  style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5),
                );
              }
              return Column(
                children: notes.map((note) {
                  final title =
                      note.title.trim().isEmpty ? 'Untitled note' : note.title;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      formatDateTime(note.updatedAt),
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 11.5,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.white70,
                    ),
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        '/field-note-editor',
                        arguments: FieldNoteEditorArgs(noteId: note.id),
                      );
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;

    if (args == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1F4E3D),
        body: Center(
          child: Text(
            'No capture details available.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final candidates = _resultCandidates(args);
    final primaryCandidate = candidates.first;
    final ObservationCandidate? secondaryCandidate =
        candidates.length > 1 ? candidates[1] : null;
    final bool hasMultipleCandidates = candidates.length > 1;
    final String votePercent =
        '${(args.top1VoteRatio * 100).toStringAsFixed(1)}%';
    final String durationSeconds = (args.windowDurationMs / 1000)
        .toStringAsFixed(1);
    final String capturedAt = _formatTimestamp(args.timestamp);
    final String resultStatusTitle = args.isConfirmed
        ? 'Capture recheck confirmed'
        : 'Uncertain scan result';
    final String scanDetailText = args.stabilityWinCount > 0
        ? 'Scan support: ${args.windowFrameCount} detections over ${durationSeconds}s, stable ${args.stabilityWinCount}/${args.stabilityWindowSize} frames'
        : 'Scan support: ${args.windowFrameCount} detections over ${durationSeconds}s';
    final String? marginPercent = secondaryCandidate == null
        ? null
        : '${((primaryCandidate.confidence - secondaryCandidate.confidence) * 100).toStringAsFixed(1)}%';
    final List<TopCandidate> topCandidates = candidates
        .map(
          (candidate) => TopCandidate(
            label: candidate.label,
            probability: candidate.confidence,
          ),
        )
        .toList(growable: false);
    final DecisionResult headlineDecision = decideHeadline(
      topK: topCandidates,
      isLichen: args.isLichen,
      existingRulesContext: ExistingRulesContext(
        headlineLabel: _selectedLabel,
      ),
    );
    final String? selectedSpeciesId =
        (_selectedSpeciesId?.trim().isNotEmpty ?? false)
        ? _selectedSpeciesId!.trim()
        : _matchedSpecies?.id;
    final String? primarySpeciesId =
        (args.speciesId?.trim().isNotEmpty ?? false)
        ? args.speciesId!.trim()
        : _matchedSpecies?.id;
    final bool canOpenSpeciesProfile =
        selectedSpeciesId != null &&
        headlineDecision.headlineRankLevel == HeadlineRankLevel.species;
    final bool canOpenMap =
        args.latitude != null && args.longitude != null;
    final _StabilityBadgeData stability =
        _stabilityFromVoteRatio(args.top1VoteRatio);
    final distributionMarkers = _matchedSpecies == null
        ? const <SpeciesMapMarker>[]
        : SpeciesMapLocationResolver.instance.resolveMarkers(_matchedSpecies!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Result'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ForestBackground(
        includeTopSafeArea: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      resultStatusTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _PhotoPreviewCard(photoPath: args.photoPath),
                    const SizedBox(height: 12),
                    _ResultCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headlineDecision.headlineLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (headlineDecision.explanationNote != null) ...[
                            Text(
                              headlineDecision.explanationNote!,
                              style: const TextStyle(
                                color: Color(0xFFD9EBD8),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (!args.isConfirmed) ...[
                            const Text(
                              'Capture recheck did not confirm a reliable species. Treat any candidate as a clue only.',
                              style: TextStyle(
                                color: Color(0xFFFFD58A),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            'Headline level: ${headlineDecision.headlineRankLevel.name}',
                            style: const TextStyle(
                              color: Color(0xCCFFFFFF),
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Lichen gate active: ${args.isLichen ? 'yes' : 'no'}',
                            style: const TextStyle(
                              color: Color(0xCCFFFFFF),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _StabilityBadge(
                                label: stability.label,
                                color: stability.color,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Vote ratio: $votePercent',
                                style: const TextStyle(
                                  color: Color(0xCCFFFFFF),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Candidates',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (int index = 0; index < candidates.length; index++) ...[
                            _CandidateCard(
                              title: _candidateTitle(index),
                              label: candidates[index].label,
                              confidence: candidates[index].confidence,
                              confidencePercent:
                                  '${(candidates[index].confidence * 100).toStringAsFixed(1)}%',
                              sourceLabel: candidates[index].modelDisplayName,
                              isSelected: _selectedCandidateIndex == index,
                              isLocked: _resultLocked,
                              onTap: (!_resultLocked && hasMultipleCandidates)
                                  ? () => _selectCandidate(index)
                                  : null,
                            ),
                            if (index < candidates.length - 1)
                              const SizedBox(height: 8),
                          ],
                          if (!_resultLocked && hasMultipleCandidates) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Tap a candidate to lock your saved label.',
                              style: TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          if (marginPercent != null)
                            Text(
                              'Top1-Top2 margin: $marginPercent',
                              style: const TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 13,
                              ),
                            ),
                          Text(
                            scanDetailText,
                            style: const TextStyle(
                              color: Color(0xCCFFFFFF),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Captured at $capturedAt',
                            style: const TextStyle(
                              color: Color(0xAAFFFFFF),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<Species?>(
                      future: _speciesFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const _ResultCard(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF8FBFA1),
                                ),
                              ),
                            ),
                          );
                        }
                        final Species? species = snapshot.data;
                        if (species == null) {
                          return const _ResultCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No matching species card found for this capture.',
                                  style: TextStyle(
                                    color: Color(0xCCFFFFFF),
                                    fontSize: 13,
                                  ),
                                ),
                                SizedBox(height: 12),
                                KeyFeaturesSection(
                                  features: <String>[],
                                ),
                              ],
                            ),
                          );
                        }
                        return _SpeciesSnapshotCard(species: species);
                      },
                    ),
                    if (args.isSavedView && args.observationId != null)
                      _buildFieldNotesPanel(args.observationId!),
                    if (!args.isSavedView || hasMultipleCandidates)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: (args.isSavedView ||
                                      !hasMultipleCandidates)
                                  ? null
                                  : _toggleLock,
                              icon: Icon(
                                _resultLocked ? Icons.lock : Icons.lock_open,
                              ),
                              label: Text(
                                _resultLocked ? 'Result Locked' : 'Lock Result',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: const StadiumBorder(),
                              ),
                            ),
                            if (hasMultipleCandidates &&
                                primarySpeciesId != null)
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pushNamed(
                                    '/species-detail',
                                    arguments: SpeciesDetailArgs(
                                      speciesId: primarySpeciesId,
                                      comparePrimaryLabel:
                                          primaryCandidate.label,
                                      compareSecondaryLabel:
                                          secondaryCandidate?.label,
                                      source: args.isSavedView
                                          ? SpeciesDetailSource
                                                .existingObservation
                                          : SpeciesDetailSource
                                                .detectionResult,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.compare_arrows),
                                label: const Text('Compare Similar'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    GlobalDistributionMapPreview(
                      scientificName: _matchedSpecies?.scientificName ??
                          _selectedLabel,
                      canonicalName: _matchedSpecies?.canonicalName,
                      speciesId: selectedSpeciesId,
                      modelId: primaryCandidate.modelId ?? args.modelId,
                      sourceClassId: primaryCandidate.sourceClassId ??
                          args.sourceClassId ??
                          args.classIndex,
                      observationLatitude: args.latitude,
                      observationLongitude: args.longitude,
                      markers: distributionMarkers,
                      emptyText:
                          'Location data not available for this species.',
                    ),
                  ],
                ),
              ),
            ),
            if (canOpenSpeciesProfile)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      '/species-detail',
                      arguments: SpeciesDetailArgs(
                        speciesId: selectedSpeciesId,
                        source: args.isSavedView
                            ? SpeciesDetailSource.existingObservation
                            : SpeciesDetailSource.detectionResult,
                      ),
                    );
                  },
                  icon: const Icon(Icons.nature),
                  label: const Text('Open species profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8FBFA1),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            if (args.isSavedView && canOpenMap) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openObservationOnMap(args),
                  icon: const Icon(Icons.map),
                  label: const Text('Open on map'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (!args.isSavedView) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_saving || !args.isConfirmed)
                      ? null
                      : () => _saveObservation(args),
                  icon: const Icon(Icons.bookmark_add),
                  label: Text(
                    _saving
                        ? 'Saving...'
                        : args.isConfirmed
                        ? 'Save Observation'
                        : 'Unconfirmed scan',
                  ),
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
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _handleBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  args.isSavedView
                      ? 'Back to observations'
                      : 'Back to detection',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTimestamp(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();
  final String year = local.year.toString().padLeft(4, '0');
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  final String second = local.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}

class _StabilityBadgeData {
  final String label;
  final Color color;

  const _StabilityBadgeData({required this.label, required this.color});
}

_StabilityBadgeData _stabilityFromVoteRatio(double ratio) {
  if (ratio >= 0.8) {
    return const _StabilityBadgeData(
      label: 'Stability: High',
      color: Color(0xFF7CD39A),
    );
  }
  if (ratio >= 0.6) {
    return const _StabilityBadgeData(
      label: 'Stability: Medium',
      color: Color(0xFFFFC857),
    );
  }
  return const _StabilityBadgeData(
    label: 'Stability: Low',
    color: Color(0xFFB0B7B4),
  );
}

class _StabilityBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StabilityBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final String title;
  final String label;
  final double confidence;
  final String confidencePercent;
  final String? sourceLabel;
  final bool isSelected;
  final bool isLocked;
  final VoidCallback? onTap;

  const _CandidateCard({
    required this.title,
    required this.label,
    required this.confidence,
    required this.confidencePercent,
    required this.sourceLabel,
    required this.isSelected,
    required this.isLocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = isSelected
        ? const Color(0xFF7CD39A)
        : const Color(0xFF8FBFA1);
    final Widget content = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? accent.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFE7F3E7),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  isLocked ? Icons.lock : Icons.check_circle,
                  color: accent,
                  size: 16,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (sourceLabel != null && sourceLabel!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Source: $sourceLabel',
              style: const TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 12.5,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: confidence.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                confidencePercent,
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: content,
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

class _PhotoPreviewCard extends StatelessWidget {
  final String? photoPath;

  const _PhotoPreviewCard({required this.photoPath});

  @override
  Widget build(BuildContext context) {
    final String? path = photoPath?.trim();
    if (path == null || path.isEmpty) {
      return const _ResultCard(
        child: Text(
          'Captured photo not available for this result.',
          style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 13),
        ),
      );
    }

    return _ResultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Captured photo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: LocalImagePreview(
                path: path,
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
        ],
      ),
    );
  }
}

class _SpeciesSnapshotCard extends StatelessWidget {
  final Species species;

  const _SpeciesSnapshotCard({required this.species});

  @override
  Widget build(BuildContext context) {
    final String description = (species.shortDescription ?? '').trim();
    final String colloquialName =
        (species.colloquialName ?? species.commonName ?? '').trim();
    final String colloquialDisplay =
        colloquialName.isEmpty ? 'Not listed' : colloquialName;
    final String habitat = (species.habitat ?? '').trim();
    final String season = (species.season ?? '').trim();
    final String distribution = species.distributionNote.trim();
    final String edibility = (species.edibilityWarning ?? '').trim();

    return _ResultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Species card',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scientific Name: ${species.scientificName}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Colloquial Name: $colloquialDisplay',
              style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13),
            ),
          ),
          const SizedBox(height: 10),
          _InfoLine(
            label: 'Taxonomy',
            value: species.taxonomyPath,
          ),
          if (description.isNotEmpty)
            _InfoLine(label: 'Description', value: description),
          const SizedBox(height: 8),
          KeyFeaturesSection(features: species.keyFeatures),
          if (habitat.isNotEmpty) _InfoLine(label: 'Habitat', value: habitat),
          if (season.isNotEmpty) _InfoLine(label: 'Season', value: season),
          if (distribution.isNotEmpty)
            _InfoLine(label: 'Distribution', value: distribution),
          if (edibility.isNotEmpty)
            _InfoLine(label: 'Safety', value: edibility),
        ],
      ),
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
      padding: const EdgeInsets.only(top: 8),
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
