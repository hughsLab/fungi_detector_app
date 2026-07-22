import '../models/mushroom_id_result.dart';
import '../models/observation.dart';

class OnlineObservationDraft {
  final String label;
  final String scientificName;
  final String? commonName;
  final double? confidence;
  final double? confidencePercent;
  final List<ObservationCandidate> candidates;
  final String notes;

  const OnlineObservationDraft({
    required this.label,
    required this.scientificName,
    required this.commonName,
    required this.confidence,
    required this.confidencePercent,
    required this.candidates,
    required this.notes,
  });
}

class MushroomIdObservationMapper {
  const MushroomIdObservationMapper();

  static const String safetyWarning =
      'Do not consume fungi based on app identification. Confirm with a qualified expert.';

  OnlineObservationDraft draftFromResult(MushroomIdResult result) {
    final top = result.topSuggestion;
    final scientificName = top?.scientificName.trim();
    final label = (scientificName == null || scientificName.isEmpty)
        ? 'Unknown fungus'
        : scientificName;
    final commonName = top?.commonNames.isNotEmpty == true
        ? top!.commonNames.first
        : null;
    final candidates = <ObservationCandidate>[
      if (top != null)
        ObservationCandidate(
          label: top.scientificName,
          confidence: top.probability,
          rawConfidence: top.probability,
          calibratedConfidence: top.probability,
          finalScore: top.probability,
        ),
      ...result.alternatives.map(
        (item) => ObservationCandidate(
          label: item.scientificName,
          confidence: item.probability,
          rawConfidence: item.probability,
          calibratedConfidence: item.probability,
          finalScore: item.probability,
        ),
      ),
    ];

    return OnlineObservationDraft(
      label: label,
      scientificName: label,
      commonName: commonName,
      confidence: top?.probability,
      confidencePercent: top?.confidencePercent,
      candidates: candidates
          .where((candidate) => candidate.label.trim().isNotEmpty)
          .take(4)
          .toList(growable: false),
      notes: _notesFor(result),
    );
  }

  String _notesFor(MushroomIdResult result) {
    final top = result.topSuggestion;
    final lines = <String>[
      safetyWarning,
      ...result.warnings.where((warning) => warning.trim().isNotEmpty),
    ];
    if (top == null) {
      lines.add('Online identification could not confidently identify this fungus.');
      return _dedupe(lines).join('\n\n');
    }
    if ((top.description ?? '').trim().isNotEmpty) {
      lines.add('Description: ${top.description!.trim()}');
    }
    if (result.alternatives.isNotEmpty) {
      lines.add(
        'Possible matches: ${result.alternatives.map((item) {
          final percent = item.confidencePercent.toStringAsFixed(1);
          return '${item.scientificName} ($percent%)';
        }).join(', ')}',
      );
    }
    return _dedupe(lines).join('\n\n');
  }

  List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final output = <String>[];
    for (final value in values) {
      final cleaned = value.trim();
      if (cleaned.isEmpty || !seen.add(cleaned.toLowerCase())) {
        continue;
      }
      output.add(cleaned);
    }
    return output;
  }
}
