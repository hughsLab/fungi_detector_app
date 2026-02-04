import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
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
  bool _saving = false;
  bool _saved = false;
  DetectionResultArgs? _args;
  String? _tempPhotoPath;
  Future<Species?>? _speciesFuture;
  bool _ownsTempPhoto = true;

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
      _speciesFuture = _loadMatchedSpecies(args);
      _ownsTempPhoto = !args.isSavedView;
    }
  }

  @override
  void dispose() {
    _cleanupTempPhoto();
    super.dispose();
  }

  Future<void> _saveObservation(DetectionResultArgs args) async {
    if (_saving) return;

    final label = args.lockedLabel.trim();
    if (label.isEmpty || label == 'Unknown') {
      _showMessage('Detection label is unavailable. Cannot save.');
      return;
    }
    final classIndex = args.classIndex;
    if (classIndex == null || classIndex < 0) {
      _showMessage('Detection class index is invalid. Cannot save.');
      return;
    }
    final confidence = args.top1AvgConf;
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
      final observation = Observation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        speciesId: (args.speciesId?.trim().isNotEmpty ?? false)
            ? args.speciesId!.trim()
            : classIndex.toString(),
        classIndex: classIndex,
        label: label,
        confidence: confidence,
        top2Label: args.top2Label,
        top2Confidence: args.top2AvgConf,
        top1VoteRatio: args.top1VoteRatio,
        windowFrameCount: args.windowFrameCount,
        windowDurationMs: args.windowDurationMs,
        stabilityWinCount: args.stabilityWinCount,
        stabilityWindowSize: args.stabilityWindowSize,
        isLichen: args.isLichen,
        timestamp: DateTime.now(),
        photoPath: photoPath,
        location: null,
        notes: null,
      );
      await _observationRepository.addObservation(observation);
      if (!mounted) return;
      _saved = true;
      _showMessage('Observation saved.');
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

    final String top1Percent =
        '${(args.top1AvgConf * 100).toStringAsFixed(1)}%';
    final String votePercent =
        '${(args.top1VoteRatio * 100).toStringAsFixed(1)}%';
    final String durationSeconds = (args.windowDurationMs / 1000)
        .toStringAsFixed(1);
    final String capturedAt = _formatTimestamp(args.timestamp);
    final String? top2Percent = args.top2AvgConf == null
        ? null
        : '${(args.top2AvgConf! * 100).toStringAsFixed(1)}%';
    final String? marginPercent = args.top2AvgConf == null
        ? null
        : '${((args.top1AvgConf - args.top2AvgConf!) * 100).toStringAsFixed(1)}%';
    final List<TopCandidate> topCandidates = [
      TopCandidate(label: args.lockedLabel, probability: args.top1AvgConf),
      if (args.top2Label != null && args.top2AvgConf != null)
        TopCandidate(label: args.top2Label!, probability: args.top2AvgConf!),
    ];
    final DecisionResult headlineDecision = decideHeadline(
      topK: topCandidates,
      isLichen: args.isLichen,
      existingRulesContext: ExistingRulesContext(
        headlineLabel: args.lockedLabel,
      ),
    );
    final bool canOpenSpeciesProfile =
        args.speciesId != null &&
        headlineDecision.headlineRankLevel == HeadlineRankLevel.species;

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
                          const Text(
                            'Top candidates',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...headlineDecision.candidates.take(5).map((
                            candidate,
                          ) {
                            final String percent =
                                '${(candidate.probability * 100).toStringAsFixed(1)}%';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '${candidate.label}: $percent',
                                style: const TextStyle(
                                  color: Color(0xCCFFFFFF),
                                  fontSize: 13,
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 10),
                          Text(
                            'Avg confidence: $top1Percent',
                            style: const TextStyle(
                              color: Color(0xCCFFFFFF),
                              fontSize: 13,
                            ),
                          ),
                          if (top2Percent != null)
                            Text(
                              '2nd confidence: $top2Percent',
                              style: const TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 13,
                              ),
                            ),
                          if (marginPercent != null)
                            Text(
                              'Top1-Top2 margin: $marginPercent',
                              style: const TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 13,
                              ),
                            ),
                          Text(
                            'Vote ratio: $votePercent',
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
                      arguments: SpeciesDetailArgs(speciesId: args.speciesId!),
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
