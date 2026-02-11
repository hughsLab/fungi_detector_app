import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../services/location_capture_service.dart';
import '../services/settings_service.dart';
import '../utils/lichen_headline_gate.dart';
import '../widgets/forest_background.dart';

class DetectionResultScreen extends StatefulWidget {
  const DetectionResultScreen({super.key});

  @override
  State<DetectionResultScreen> createState() => _DetectionResultScreenState();
}

class _DetectionResultScreenState extends State<DetectionResultScreen> {
  final ObservationRepository _observationRepository =
      ObservationRepository.instance;
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;
  final SettingsService _settingsService = SettingsService.instance;
  final LocationCaptureService _locationCaptureService =
      LocationCaptureService.instance;
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
    _selectedCandidateIndex = 0;
    _selectedLabel = args.lockedLabel;
    _selectedConfidence = args.top1AvgConf;
    _selectedClassIndex = args.classIndex;
    _selectedSpeciesId = args.speciesId;
    final bool hasSecondary =
        args.top2Label != null && args.top2AvgConf != null;
    _resultLocked = args.isSavedView || !hasSecondary;
  }

  void _selectCandidate(int index) {
    final args = _args;
    if (args == null) return;
    if (_resultLocked) return;

    if (index == 0) {
      setState(() {
        _selectedCandidateIndex = 0;
        _selectedLabel = args.lockedLabel;
        _selectedConfidence = args.top1AvgConf;
        _selectedClassIndex = args.classIndex;
        _selectedSpeciesId = args.speciesId ?? _matchedSpecies?.id;
      });
      return;
    }

    if (index == 1 && args.top2Label != null && args.top2AvgConf != null) {
      setState(() {
        _selectedCandidateIndex = 1;
        _selectedLabel = args.top2Label!;
        _selectedConfidence = args.top2AvgConf!;
        _selectedClassIndex = args.top2ClassIndex;
        _selectedSpeciesId = args.top2ClassIndex?.toString();
      });
    }
  }

  void _toggleLock() {
    if (_args?.isSavedView ?? false) return;
    setState(() {
      _resultLocked = !_resultLocked;
    });
  }

  Future<void> _saveObservation(DetectionResultArgs args) async {
    if (_saving) return;

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

    setState(() {
      _saving = true;
    });
    try {
      String? photoPath;
      if (args.photoPath != null) {
        photoPath = await _persistPhoto(args.photoPath!);
      }
      final bool swapped = _selectedCandidateIndex == 1;
      final String? top2LabelToStore = swapped ? args.lockedLabel : args.top2Label;
      final double? top2ConfidenceToStore = swapped
          ? args.top1AvgConf
          : args.top2AvgConf;
      final settings = await _settingsService.loadSettings();
      CapturedLocation? capturedLocation;
      String? locationMessage;
      ObservationLocationSource locationSource = ObservationLocationSource.none;
      double? latitude;
      double? longitude;
      double? accuracyMeters;
      DateTime? capturedAt;
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
        }
      }

      final observation = Observation(
        id: _uuid.v4(),
        speciesId: (_selectedSpeciesId?.trim().isNotEmpty ?? false)
            ? _selectedSpeciesId!.trim()
            : classIndex.toString(),
        classIndex: classIndex,
        label: label,
        confidence: confidence,
        top2Label: top2LabelToStore,
        top2Confidence: top2ConfidenceToStore,
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
        notes: null,
      );
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
      if (!mounted) return;
      setState(() {
        _saving = false;
      });
    }
  }

  Future<Species?> _loadMatchedSpecies(DetectionResultArgs args) async {
    final String? speciesId = args.speciesId?.trim();
    if (speciesId != null && speciesId.isNotEmpty) {
      final Species? exact = await _speciesRepository.getById(speciesId);
      if (exact != null) {
        return exact;
      }
    }

    final String normalizedLabel = args.lockedLabel.trim().toLowerCase();
    if (normalizedLabel.isEmpty) {
      return null;
    }

    final all = await _speciesRepository.loadSpecies();
    for (final item in all) {
      if (item.scientificName.trim().toLowerCase() == normalizedLabel) {
        return item;
      }
      final String common = (item.commonName ?? '').trim().toLowerCase();
      if (common.isNotEmpty && common == normalizedLabel) {
        return item;
      }
    }
    return null;
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

    final bool hasSecondaryCandidate =
        args.top2Label != null && args.top2AvgConf != null;
    final String top1Percent =
        '${(args.top1AvgConf * 100).toStringAsFixed(1)}%';
    final String votePercent =
        '${(args.top1VoteRatio * 100).toStringAsFixed(1)}%';
    final String durationSeconds = (args.windowDurationMs / 1000)
        .toStringAsFixed(1);
    final String capturedAt = _formatTimestamp(args.timestamp);
    final String? top2Percent = hasSecondaryCandidate
        ? '${(args.top2AvgConf! * 100).toStringAsFixed(1)}%'
        : null;
    final String? marginPercent = hasSecondaryCandidate
        ? '${((args.top1AvgConf - args.top2AvgConf!) * 100).toStringAsFixed(1)}%'
        : null;
    final List<TopCandidate> topCandidates = [
      TopCandidate(label: args.lockedLabel, probability: args.top1AvgConf),
      if (hasSecondaryCandidate)
        TopCandidate(label: args.top2Label!, probability: args.top2AvgConf!),
    ];
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
    final _StabilityBadgeData stability =
        _stabilityFromVoteRatio(args.top1VoteRatio);

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
                    const Text(
                      'Stable detection captured',
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
                          _CandidateCard(
                            title: 'Primary Candidate',
                            label: args.lockedLabel,
                            confidence: args.top1AvgConf,
                            confidencePercent: top1Percent,
                            isSelected: _selectedCandidateIndex == 0,
                            isLocked: _resultLocked,
                            onTap: (!_resultLocked && hasSecondaryCandidate)
                                ? () => _selectCandidate(0)
                                : null,
                          ),
                          const SizedBox(height: 8),
                          if (hasSecondaryCandidate)
                            _CandidateCard(
                              title: 'Secondary Candidate',
                              label: args.top2Label ?? 'Unknown',
                              confidence: args.top2AvgConf ?? 0.0,
                              confidencePercent: top2Percent ?? '--',
                              isSelected: _selectedCandidateIndex == 1,
                              isLocked: _resultLocked,
                              onTap: _resultLocked
                                  ? null
                                  : () => _selectCandidate(1),
                            )
                          else
                            const _CandidateEmptyCard(
                              title: 'Secondary Candidate',
                              message: 'Not available for this capture.',
                            ),
                          if (!_resultLocked && hasSecondaryCandidate) ...[
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
                            'Stable for ${args.stabilityWinCount}/${args.stabilityWindowSize} frames over ${durationSeconds}s',
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
                            child: Text(
                              'No matching species card found for this capture.',
                              style: TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 13,
                              ),
                            ),
                          );
                        }
                        return _SpeciesSnapshotCard(species: species);
                      },
                    ),
                    if (!args.isSavedView || hasSecondaryCandidate)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: (args.isSavedView ||
                                      !hasSecondaryCandidate)
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
                            if (hasSecondaryCandidate &&
                                primarySpeciesId != null)
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pushNamed(
                                    '/species-detail',
                                    arguments: SpeciesDetailArgs(
                                      speciesId: primarySpeciesId!,
                                      comparePrimaryLabel: args.lockedLabel,
                                      compareSecondaryLabel: args.top2Label,
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
                      arguments: SpeciesDetailArgs(speciesId: selectedSpeciesId!),
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
            const SizedBox(height: 12),
            if (!args.isSavedView) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : () => _saveObservation(args),
                  icon: const Icon(Icons.bookmark_add),
                  label: Text(_saving ? 'Saving...' : 'Save Observation'),
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
  final bool isSelected;
  final bool isLocked;
  final VoidCallback? onTap;

  const _CandidateCard({
    required this.title,
    required this.label,
    required this.confidence,
    required this.confidencePercent,
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

class _CandidateEmptyCard extends StatelessWidget {
  final String title;
  final String message;

  const _CandidateEmptyCard({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFE7F3E7),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 13,
            ),
          ),
        ],
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
    final String? path = photoPath;
    final bool hasImage = path != null && File(path).existsSync();
    if (!hasImage) {
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
              child: Image.file(File(path), fit: BoxFit.cover),
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
    final String commonName = (species.commonName ?? '').trim();
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
            species.scientificName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (commonName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                commonName,
                style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13),
              ),
            ),
          const SizedBox(height: 10),
          _InfoLine(
            label: 'Taxonomy',
            value: [
              species.taxonomyKingdom,
              species.taxonomyPhylum,
              species.taxonomyClass,
              species.taxonomyOrder,
              species.taxonomyFamily,
              species.taxonomyGenus,
              species.taxonomySpecies,
            ].whereType<String>().where((v) => v.trim().isNotEmpty).join(' > '),
          ),
          if (description.isNotEmpty)
            _InfoLine(label: 'Description', value: description),
          if (species.keyFeatures.isNotEmpty)
            _InfoLine(
              label: 'Key features',
              value: species.keyFeatures
                  .where((f) => f.trim().isNotEmpty)
                  .map((f) => '- ${f.trim()}')
                  .join('\n'),
            ),
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
