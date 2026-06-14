import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/observation.dart';

void main() {
  test('observation candidates round-trip through json', () {
    final observation = Observation(
      id: 'obs-1',
      speciesId: 'model_2:0',
      classIndex: 0,
      modelId: 'model_2',
      modelDisplayName: 'Model 2',
      sourceClassId: 0,
      label: 'Agaricus campestris',
      confidence: 0.70,
      top2Label: 'Agaricus xanthodermus',
      top2Confidence: 0.63,
      top2ModelId: 'model_1',
      top2ModelDisplayName: 'Model 1',
      top2SourceClassId: 12,
      candidates: const <ObservationCandidate>[
        ObservationCandidate(
          label: 'Agaricus campestris',
          confidence: 0.70,
          classIndex: 0,
          speciesId: 'model_2:0',
          modelId: 'model_2',
          modelDisplayName: 'Model 2',
          sourceClassId: 0,
        ),
        ObservationCandidate(
          label: 'Agaricus xanthodermus',
          confidence: 0.63,
          classIndex: 12,
          modelId: 'model_1',
          modelDisplayName: 'Model 1',
          sourceClassId: 12,
        ),
        ObservationCandidate(
          label: 'Leucopaxillus eucalyptorum',
          confidence: 0.48,
          classIndex: 34,
          modelId: 'merged',
          modelDisplayName: 'Merged',
          sourceClassId: 34,
        ),
      ],
      createdAt: DateTime.utc(2026, 6, 8),
      photoPath: null,
    );

    final restored = Observation.fromJson(observation.toJson());

    expect(restored.candidates, hasLength(3));
    expect(restored.candidates[0].label, 'Agaricus campestris');
    expect(restored.candidates[1].modelDisplayName, 'Model 1');
    expect(restored.candidates[2].confidence, 0.48);
  });

  test('legacy observation without candidates still parses', () {
    final restored = Observation.fromJson({
      'id': 'legacy',
      'speciesId': '1',
      'classIndex': 1,
      'label': 'Amanita muscaria',
      'confidence': 0.82,
      'createdAt': '2026-06-08T00:00:00.000Z',
    });

    expect(restored.label, 'Amanita muscaria');
    expect(restored.candidates, isEmpty);
  });
}
