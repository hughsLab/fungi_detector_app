import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/utils/lichen_headline_gate.dart';

void main() {
  test('lichen with top1=0.61 and top2=0.24 is downgraded', () {
    final DecisionResult result = decideHeadline(
      topK: const [
        TopCandidate(label: 'Rhizocarpon geographicum', probability: 0.61),
        TopCandidate(label: 'Buellia aethalea', probability: 0.24),
      ],
      isLichen: true,
      existingRulesContext: const ExistingRulesContext(
        headlineLabel: 'Rhizocarpon geographicum',
      ),
    );

    expect(result.headlineRankLevel, isNot(HeadlineRankLevel.species));
    expect(result.headlineLabel, contains('Lichen'));
    expect(result.explanationNote, lichenHeadlineLimitNote);
  });

  test('lichen with top1=0.88 and top2=0.12 allows species headline', () {
    final DecisionResult result = decideHeadline(
      topK: const [
        TopCandidate(label: 'Rhizocarpon geographicum', probability: 0.88),
        TopCandidate(label: 'Buellia aethalea', probability: 0.12),
      ],
      isLichen: true,
      existingRulesContext: const ExistingRulesContext(
        headlineLabel: 'Rhizocarpon geographicum',
      ),
    );

    expect(result.headlineRankLevel, HeadlineRankLevel.species);
    expect(result.headlineLabel, 'Rhizocarpon geographicum');
    expect(result.explanationNote, isNull);
  });

  test('mushroom with top1=0.74 and top2=0.20 keeps existing rules', () {
    final DecisionResult result = decideHeadline(
      topK: const [
        TopCandidate(label: 'Amanita muscaria', probability: 0.74),
        TopCandidate(label: 'Amanita pantherina', probability: 0.20),
      ],
      isLichen: false,
      existingRulesContext: const ExistingRulesContext(
        headlineLabel: 'Amanita muscaria',
      ),
    );

    expect(result.headlineRankLevel, HeadlineRankLevel.species);
    expect(result.headlineLabel, 'Amanita muscaria');
    expect(result.explanationNote, isNull);
  });
}
