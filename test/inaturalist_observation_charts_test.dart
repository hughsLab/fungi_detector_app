import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/inaturalist_observation_histogram.dart';
import 'package:realtime_detection_app/repositories/inaturalist_cache_repository.dart';
import 'package:realtime_detection_app/services/inaturalist_rate_limiter.dart';
import 'package:realtime_detection_app/services/inaturalist_service.dart';
import 'package:realtime_detection_app/widgets/inaturalist_observation_charts.dart';

void main() {
  testWidgets('renders seasonal and history public-observation charts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1F4E3D),
          body: SingleChildScrollView(
            child: INaturalistObservationCharts(
              taxonId: 1,
              scientificName: 'Amanita example',
              service: _FakeINaturalistService(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Public observation charts'), findsOneWidget);
    expect(find.text('Seasonal observations'), findsOneWidget);
    expect(find.text('Observation history'), findsOneWidget);
    expect(find.textContaining('reporting activity'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}

class _FakeINaturalistService extends INaturalistService {
  _FakeINaturalistService()
    : super(
        cache: MemoryINaturalistCacheStore(),
        histogramCache: MemoryINaturalistHistogramCacheStore(),
        rateLimiter: INaturalistRateLimiter(minimumInterval: Duration.zero),
      );

  @override
  Future<INaturalistObservationHistogram?> getObservationHistogramForTaxon(
    int taxonId,
  ) async => INaturalistObservationHistogram(
    taxonId: taxonId,
    observationsByMonth: const {1: 4, 4: 12, 10: 30},
    observationsByYear: const {2023: 6, 2024: 10, 2025: 18},
    fetchedAt: DateTime(2026),
    expiresAt: DateTime(2027),
  );
}
