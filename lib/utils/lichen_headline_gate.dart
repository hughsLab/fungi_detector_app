enum HeadlineRankLevel { species, genus, complex }

class TopCandidate {
  final String label;
  final double probability;

  const TopCandidate({required this.label, required this.probability});
}

class ExistingRulesContext {
  final String headlineLabel;
  final HeadlineRankLevel headlineRankLevel;

  const ExistingRulesContext({
    required this.headlineLabel,
    this.headlineRankLevel = HeadlineRankLevel.species,
  });
}

class DecisionResult {
  final String headlineLabel;
  final HeadlineRankLevel headlineRankLevel;
  final String? explanationNote;
  final List<TopCandidate> candidates;

  const DecisionResult({
    required this.headlineLabel,
    required this.headlineRankLevel,
    required this.explanationNote,
    required this.candidates,
  });
}

const String lichenHeadlineLimitNote =
    'Species-level ID limited for lichens due to high visual similarity between taxa.';

DecisionResult decideHeadline({
  required List<TopCandidate> topK,
  required bool isLichen,
  required ExistingRulesContext existingRulesContext,
}) {
  final List<TopCandidate> candidates = [...topK]
    ..sort((a, b) => b.probability.compareTo(a.probability));

  if (!isLichen) {
    return DecisionResult(
      headlineLabel: existingRulesContext.headlineLabel,
      headlineRankLevel: existingRulesContext.headlineRankLevel,
      explanationNote: null,
      candidates: candidates,
    );
  }

  if (candidates.isEmpty) {
    return DecisionResult(
      headlineLabel: existingRulesContext.headlineLabel,
      headlineRankLevel: existingRulesContext.headlineRankLevel,
      explanationNote: null,
      candidates: candidates,
    );
  }

  final TopCandidate top1 = candidates.first;
  final double top2Probability = candidates.length > 1
      ? candidates[1].probability
      : 0.0;
  final bool allowSpeciesHeadline =
      top1.probability >= 0.80 && (top1.probability - top2Probability) >= 0.20;

  if (allowSpeciesHeadline) {
    return DecisionResult(
      headlineLabel: top1.label,
      headlineRankLevel: HeadlineRankLevel.species,
      explanationNote: null,
      candidates: candidates,
    );
  }

  final _DowngradedHeadline downgraded = _buildDowngradedLichenHeadline(
    candidates,
  );
  return DecisionResult(
    headlineLabel: downgraded.label,
    headlineRankLevel: downgraded.level,
    explanationNote: lichenHeadlineLimitNote,
    candidates: candidates,
  );
}

_DowngradedHeadline _buildDowngradedLichenHeadline(List<TopCandidate> topK) {
  final List<String> genera = <String>[];
  for (final candidate in topK.take(3)) {
    final String genus = _extractGenus(candidate.label);
    if (genus.isEmpty || genera.contains(genus)) {
      continue;
    }
    genera.add(genus);
  }

  if (genera.length == 1) {
    return _DowngradedHeadline(
      label: '${genera.first} sp. (lichen)',
      level: HeadlineRankLevel.genus,
    );
  }

  if (genera.length > 1) {
    return _DowngradedHeadline(
      label: 'Lichen (${genera.join('/')} complex)',
      level: HeadlineRankLevel.complex,
    );
  }

  return const _DowngradedHeadline(
    label: 'Lichen complex',
    level: HeadlineRankLevel.complex,
  );
}

String _extractGenus(String label) {
  final String trimmed = label.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final List<String> tokens = trimmed.split(RegExp(r'[\s_]+'));
  if (tokens.isEmpty) {
    return '';
  }
  final String cleaned = tokens.first.replaceAll(RegExp(r'[^A-Za-z-]'), '');
  if (cleaned.isEmpty) {
    return '';
  }
  final String lower = cleaned.toLowerCase();
  return '${lower[0].toUpperCase()}${lower.substring(1)}';
}

class _DowngradedHeadline {
  final String label;
  final HeadlineRankLevel level;

  const _DowngradedHeadline({required this.label, required this.level});
}
