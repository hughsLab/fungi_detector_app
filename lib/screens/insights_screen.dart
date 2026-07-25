import 'dart:async';

import 'package:flutter/material.dart';

import '../models/insight_statistics.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../services/insights_service.dart';

typedef ObservationLoader = Future<List<Observation>> Function();
typedef SpeciesLoader = Future<List<Species>> Function();
typedef GlobalObservationStream = Stream<List<Observation>> Function();

DateTime _systemNow() => DateTime.now();

class InsightsScreen extends StatefulWidget {
  final ObservationLoader? personalLoader;
  final SpeciesLoader? speciesLoader;
  final GlobalObservationStream? globalStream;
  final InsightsService insightsService;
  final DateTime Function() now;

  const InsightsScreen({
    super.key,
    this.personalLoader,
    this.speciesLoader,
    this.globalStream,
    this.insightsService = const InsightsService(),
    this.now = _systemNow,
  });

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  ObservationRepository get _observations => ObservationRepository.instance;
  SpeciesRepository get _speciesRepository => SpeciesRepository.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Species> _species = const [];
  List<Observation> _personal = const [];
  List<Observation> _global = const [];
  InsightStatistics? _statistics;
  InsightScope _scope = InsightScope.personal;
  SpeciesInsightSort _sort = SpeciesInsightSort.mostDetected;
  String _query = '';
  Object? _error;
  bool _loading = true;
  StreamSubscription<List<Observation>>? _localSubscription;
  StreamSubscription<List<Observation>>? _globalSubscription;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearch);
    if (widget.personalLoader == null) {
      _localSubscription = _observations.watchObservationChanges().listen((
        items,
      ) {
        _personal = items;
        if (_scope == InsightScope.personal) _recalculate();
      });
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _localSubscription?.cancel();
    _globalSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final personal =
          await (widget.personalLoader?.call() ??
              _observations.loadObservations());
      final species =
          await (widget.speciesLoader?.call() ??
              _speciesRepository.loadSpecies());
      if (!mounted) return;
      _personal = personal;
      _species = species;
      _recalculate();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _selectScope(InsightScope scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _loading = scope == InsightScope.global && _global.isEmpty;
      _error = null;
    });
    if (scope == InsightScope.global && _globalSubscription == null) {
      final stream =
          widget.globalStream?.call() ??
          _observations.streamPublicInsightObservations(limit: 300);
      _globalSubscription = stream.listen(
        (items) {
          _global = items;
          if (_scope == InsightScope.global) _recalculate();
        },
        onError: (Object error) {
          if (!mounted || _scope != InsightScope.global) return;
          setState(() {
            _error = error;
            _loading = false;
          });
        },
      );
    } else {
      _recalculate();
    }
  }

  void _recalculate() {
    final items = _scope == InsightScope.personal ? _personal : _global;
    final result = widget.insightsService.calculate(
      observations: items,
      species: _species,
      now: widget.now(),
      publicOnly: _scope == InsightScope.global,
      isLimitedSnapshot: _scope == InsightScope.global,
    );
    if (!mounted) return;
    setState(() {
      _statistics = result;
      _loading = false;
      _error = null;
    });
  }

  void _handleSearch() {
    final value = _searchController.text.trim().toLowerCase();
    if (value != _query) setState(() => _query = value);
  }

  List<SpeciesInsight> _visibleSpecies(InsightStatistics statistics) {
    final items = statistics.species
        .where(
          (item) =>
              _query.isEmpty ||
              item.commonName.toLowerCase().contains(_query) ||
              item.scientificName.toLowerCase().contains(_query),
        )
        .toList();
    switch (_sort) {
      case SpeciesInsightSort.mostDetected:
        items.sort((a, b) => b.detectionCount.compareTo(a.detectionCount));
      case SpeciesInsightSort.leastDetected:
        items.sort((a, b) => a.detectionCount.compareTo(b.detectionCount));
      case SpeciesInsightSort.mostRecent:
        items.sort((a, b) => b.lastDetectedAt.compareTo(a.lastDetectedAt));
      case SpeciesInsightSort.highestConfidence:
        items.sort(
          (a, b) =>
              (b.highestConfidence ?? -1).compareTo(a.highestConfidence ?? -1),
        );
      case SpeciesInsightSort.rareSpecies:
        items.sort(
          (a, b) => _rarityRank(b.rarity).compareTo(_rarityRank(a.rarity)),
        );
      case SpeciesInsightSort.poisonousSpecies:
        items.sort(
          (a, b) =>
              _toxicityRank(b.toxicity).compareTo(_toxicityRank(a.toxicity)),
        );
      case SpeciesInsightSort.alphabetical:
        items.sort(
          (a, b) =>
              a.commonName.toLowerCase().compareTo(b.commonName.toLowerCase()),
        );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5EF),
      appBar: AppBar(
        title: const Text('Insights'),
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF1F6F47),
        actions: [
          IconButton(
            tooltip: 'Refresh insights',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _ScopeSelector(scope: _scope, onSelected: _selectScope),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(key: Key('insights-loading')),
      );
    }
    if (_error != null) {
      return _ErrorState(
        onRetry: _scope == InsightScope.personal
            ? _load
            : () {
                _globalSubscription?.cancel();
                _globalSubscription = null;
                _selectScope(InsightScope.personal);
                _selectScope(InsightScope.global);
              },
      );
    }
    final statistics = _statistics;
    if (statistics == null || statistics.totalObservations == 0) {
      return const _EmptyState();
    }
    final species = _visibleSpecies(statistics);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (statistics.isLimitedSnapshot)
            const _Notice(
              icon: Icons.public,
              text:
                  'Global Insights is a read-only snapshot of up to 300 public observations. Counts may not represent the complete global collection.',
            ),
          _SummaryGrid(statistics: statistics),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Detections by Species',
            subtitle: 'Counts reflect saved, identified observations.',
            child: Column(
              children: [
                TextField(
                  key: const Key('insights-species-search'),
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search common or scientific name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<SpeciesInsightSort>(
                  key: const Key('insights-sort'),
                  value: _sort,
                  decoration: const InputDecoration(
                    labelText: 'Sort species',
                    border: OutlineInputBorder(),
                  ),
                  items: SpeciesInsightSort.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_sortLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                ),
                const SizedBox(height: 8),
                if (species.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No species match your search.'),
                  ),
                for (final item in species.take(100))
                  _SpeciesRow(
                    key: ValueKey('species-${item.key}'),
                    insight: item,
                  ),
                if (species.length > 100)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Showing the first 100 of ${species.length} species. Refine your search to see more.',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _RarityCard(statistics: statistics),
          const SizedBox(height: 16),
          _ToxicityCard(statistics: statistics),
          const SizedBox(height: 16),
          _INaturalistInsightsCard(statistics: statistics),
          const SizedBox(height: 16),
          _TrendCard(statistics: statistics),
          const SizedBox(height: 16),
          _LocationCard(statistics: statistics),
          const SizedBox(height: 16),
          _ConfidenceCard(statistics: statistics),
          const SizedBox(height: 16),
          const _Notice(
            icon: Icons.warning_amber_rounded,
            text:
                'Never consume a fungus based only on an application identification. Identification and toxicity information may be incomplete or incorrect.',
          ),
        ],
      ),
    );
  }
}

class _ScopeSelector extends StatelessWidget {
  final InsightScope scope;
  final ValueChanged<InsightScope> onSelected;
  const _ScopeSelector({required this.scope, required this.onSelected});
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF1F6F47),
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: SizedBox(
      width: double.infinity,
      child: SegmentedButton<InsightScope>(
        segments: const [
          ButtonSegment(
            value: InsightScope.personal,
            label: Text('My Insights'),
            icon: Icon(Icons.person_outline),
          ),
          ButtonSegment(
            value: InsightScope.global,
            label: Text('Global Insights'),
            icon: Icon(Icons.public),
          ),
        ],
        selected: {scope},
        onSelectionChanged: (values) => onSelected(values.first),
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? const Color(0xFFE3F2E8)
                : Colors.white,
          ),
          foregroundColor: const WidgetStatePropertyAll(Color(0xFF174D34)),
        ),
      ),
    ),
  );
}

class _SummaryGrid extends StatelessWidget {
  final InsightStatistics statistics;
  const _SummaryGrid({required this.statistics});
  @override
  Widget build(BuildContext context) {
    final toxicityAvailable =
        statistics.toxicitySpeciesCounts[ToxicityCategory.unknown] !=
        statistics.uniqueSpecies;
    final rarityAvailable =
        statistics.raritySpeciesCounts[SpeciesRarity.unknown] !=
        statistics.uniqueSpecies;
    final cards = [
      (
        'Total observations',
        '${statistics.totalObservations}',
        Icons.collections_bookmark_outlined,
      ),
      (
        'Saved detections',
        '${statistics.totalDetections}',
        Icons.center_focus_strong_outlined,
      ),
      ('Unique species', '${statistics.uniqueSpecies}', Icons.eco_outlined),
      (
        'Poisonous detections',
        toxicityAvailable
            ? '${statistics.poisonousObservations}'
            : 'Not available',
        Icons.warning_amber_rounded,
      ),
      (
        'Rare detections',
        rarityAvailable ? '${statistics.rareObservations}' : 'Not available',
        Icons.auto_awesome_outlined,
      ),
      (
        'Unidentified',
        '${statistics.unidentifiedObservations}',
        Icons.help_outline,
      ),
      ('Online', '${statistics.onlineDetections}', Icons.cloud_outlined),
      (
        'Offline',
        '${statistics.offlineDetections}',
        Icons.phone_android_outlined,
      ),
      ('Pending sync', '${statistics.pendingCloudSync}', Icons.sync_outlined),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: cards
              .map(
                (item) => SizedBox(
                  width: width,
                  child: _SummaryCard(
                    label: item.$1,
                    value: item.$2,
                    icon: item.$3,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Card(
    key: Key('summary-${label.toLowerCase().replaceAll(' ', '-')}'),
    elevation: 0,
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF2D774E)),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: value == 'Not available' ? 13 : 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF173D2A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            style: const TextStyle(fontSize: 11, color: Color(0xFF607069)),
          ),
        ],
      ),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _SectionCard({required this.title, this.subtitle, required this.child});
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Color(0xFF173D2A),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(color: Color(0xFF607069))),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

class _SpeciesRow extends StatelessWidget {
  final SpeciesInsight insight;
  const _SpeciesRow({super.key, required this.insight});
  @override
  Widget build(BuildContext context) {
    final warning =
        insight.toxicity == ToxicityCategory.deadly ||
        insight.toxicity == ToxicityCategory.poisonous ||
        insight.toxicity == ToxicityCategory.potentiallyPoisonous;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumbnail(path: insight.thumbnailAssetPath),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        insight.commonName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    if (warning)
                      const Tooltip(
                        message: 'Poisonous or potentially poisonous',
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFB23A2E),
                          size: 20,
                        ),
                      ),
                  ],
                ),
                Text(
                  insight.scientificName,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF607069),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${insight.detectionCount} detections • ${insight.percentage.toStringAsFixed(1)}% • ${_sourceLabel(insight.source)}',
                ),
                Text(
                  'Last: ${_date(insight.lastDetectedAt)} • Avg: ${_percent(insight.averageConfidence)} • High: ${_percent(insight.highestConfidence)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF607069),
                  ),
                ),
                Text(
                  '${insight.savedObservationCount} saved observations',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF607069),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String? path;
  const _Thumbnail({required this.path});
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: const Color(0xFFE7EFE8),
      alignment: Alignment.center,
      child: const Icon(Icons.eco_outlined, color: Color(0xFF2D774E)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 58,
        height: 58,
        child: path == null || path!.isEmpty
            ? fallback
            : Image.asset(
                path!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _RarityCard extends StatelessWidget {
  final InsightStatistics statistics;
  const _RarityCard({required this.statistics});
  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Rarity',
    subtitle:
        'Biological rarity is kept separate from how often you detect a species.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rarity in SpeciesRarity.values)
          _BreakdownRow(
            label: _rarityLabel(rarity),
            count: statistics.raritySpeciesCounts[rarity] ?? 0,
            total: statistics.uniqueSpecies,
          ),
        if (statistics.rareSpecies.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'No detected species has an explicit rare classification in the current species data.',
            ),
          ),
        const SizedBox(height: 10),
        const Text(
          'Rarity classification is based on the species information available in the application and may vary by region.',
          style: TextStyle(fontSize: 12, color: Color(0xFF607069)),
        ),
      ],
    ),
  );
}

class _ToxicityCard extends StatelessWidget {
  final InsightStatistics statistics;
  const _ToxicityCard({required this.statistics});
  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Toxicity detections',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final value in ToxicityCategory.values)
          _BreakdownRow(
            label: _toxicityLabel(value),
            count: statistics.toxicityObservationCounts[value] ?? 0,
            total: statistics.totalObservations,
          ),
        const SizedBox(height: 8),
        if (statistics.poisonousSpeciesList.isEmpty)
          const Text(
            'No saved observation contains explicit poisonous or potentially poisonous metadata.',
          )
        else
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      'Poisonous observations: ${statistics.poisonousObservations} • Most detected: ',
                ),
                TextSpan(
                  text:
                      statistics.mostDetectedPoisonousSpecies?.commonName ??
                      'Not available',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        for (final item in statistics.poisonousSpeciesList)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFB23A2E),
            ),
            title: Text(
              item.commonName,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            subtitle: Text(
              item.scientificName,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            trailing: Text('${item.detectionCount}'),
          ),
      ],
    ),
  );
}

class _INaturalistInsightsCard extends StatelessWidget {
  final InsightStatistics statistics;
  const _INaturalistInsightsCard({required this.statistics});

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'iNaturalist public statistics',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Matched species: ${statistics.iNaturalistMatchedSpecies}'),
        Text('Unmatched species: ${statistics.iNaturalistUnmatchedSpecies}'),
        Text('Stale cached records: ${statistics.staleINaturalistRecords}'),
        if (statistics.mostPubliclyObservedSpecies != null)
          _InlineSpeciesStatistic(
            label: 'Most publicly observed',
            name: statistics.mostPubliclyObservedSpecies!.commonName,
            value:
                '${statistics.mostPubliclyObservedSpecies!.iNaturalistGlobalObservationCount}',
          ),
        if (statistics.leastPubliclyObservedSpecies != null)
          _InlineSpeciesStatistic(
            label: 'Lowest iNaturalist observation count',
            name: statistics.leastPubliclyObservedSpecies!.commonName,
            value:
                '${statistics.leastPubliclyObservedSpecies!.iNaturalistGlobalObservationCount}',
          ),
        for (final entry in statistics.conservationStatusCounts.entries)
          Text('${entry.key}: ${entry.value} species'),
        const SizedBox(height: 8),
        const Text(
          'Public observation counts show reporting frequency on iNaturalist '
          'and do not necessarily indicate biological rarity.',
          style: TextStyle(fontSize: 12, color: Color(0xFF607069)),
        ),
      ],
    ),
  );
}

class _TrendCard extends StatelessWidget {
  final InsightStatistics statistics;
  const _TrendCard({required this.statistics});
  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Observation Trends',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricLine('Last 7 days', '${statistics.observationsLast7Days}'),
        _MetricLine('Last 30 days', '${statistics.observationsLast30Days}'),
        _MetricLine(
          'Most active month',
          statistics.mostActiveMonth ?? 'Not available',
        ),
        _MetricLine(
          'Most active day',
          statistics.mostActiveWeekday ?? 'Not available',
        ),
        _MetricLine(
          'Average per active month',
          statistics.averageObservationsPerActiveMonth?.toStringAsFixed(1) ??
              'Not available',
        ),
        _MetricLine(
          'New species this month',
          '${statistics.newSpeciesThisMonth}',
        ),
        _MetricLine(
          'First-time / repeat detections',
          '${statistics.firstTimeDetections} / ${statistics.repeatDetections}',
        ),
        const SizedBox(height: 10),
        for (final entry in statistics.observationsByMonth.entries)
          _BarRow(
            label: entry.key,
            value: entry.value,
            maximum: statistics.observationsByMonth.values.fold(
              0,
              (a, b) => a > b ? a : b,
            ),
          ),
      ],
    ),
  );
}

class _LocationCard extends StatelessWidget {
  final InsightStatistics statistics;
  const _LocationCard({required this.statistics});
  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Location Insights',
    subtitle: 'Only broad labels and aggregate coordinate counts are shown.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricLine(
          'With coordinates',
          '${statistics.observationsWithCoordinates}',
        ),
        _MetricLine(
          'Without coordinates',
          '${statistics.observationsWithoutCoordinates}',
        ),
        _MetricLine(
          'Unique mapped areas',
          '${statistics.uniqueMappedLocations}',
        ),
        _MetricLine(
          'Most active location',
          statistics.mostActiveLocation ?? 'Not available',
        ),
        if (statistics.countryCounts.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'Countries',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final entry in statistics.countryCounts.entries.take(8))
            _MetricLine(entry.key, '${entry.value}'),
        ],
        if (statistics.regionCounts.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'States & regions',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final entry in statistics.regionCounts.entries.take(8))
            _MetricLine(entry.key, '${entry.value}'),
        ],
      ],
    ),
  );
}

class _ConfidenceCard extends StatelessWidget {
  final InsightStatistics statistics;
  const _ConfidenceCard({required this.statistics});
  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Confidence Insights',
    child: Column(
      children: [
        _MetricLine(
          'Average confidence',
          _percent(statistics.averageConfidence),
        ),
        if (statistics.highestConfidenceDetection == null)
          const _MetricLine('Highest-confidence species', 'Not available')
        else
          _SpeciesMetricLine(
            label: 'Highest-confidence species',
            name: statistics.highestConfidenceDetection!.commonName,
            value: _percent(
              statistics.highestConfidenceDetection!.highestConfidence,
            ),
          ),
        _MetricLine(
          'Lowest saved detection',
          _percent(statistics.lowestSavedConfidence),
        ),
        _MetricLine(
          'High / medium / low',
          '${statistics.highConfidenceDetections} / ${statistics.mediumConfidenceDetections} / ${statistics.lowConfidenceDetections}',
        ),
        _MetricLine(
          'Online average',
          _percent(statistics.averageOnlineConfidence),
        ),
        _MetricLine(
          'Offline average',
          _percent(statistics.averageOfflineConfidence),
        ),
        _MetricLine(
          'Average top result gap',
          _percent(statistics.averagePrimarySecondaryGap),
        ),
      ],
    ),
  );
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  const _BreakdownRow({
    required this.label,
    required this.count,
    required this.total,
  });
  @override
  Widget build(BuildContext context) => _BarRow(
    label: label,
    value: count,
    maximum: total,
    suffix: total == 0 ? '0%' : '${(count * 100 / total).toStringAsFixed(0)}%',
  );
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int maximum;
  final String? suffix;
  const _BarRow({
    required this.label,
    required this.value,
    required this.maximum,
    this.suffix,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 86,
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: maximum == 0 ? 0 : value / maximum,
              minHeight: 8,
              color: const Color(0xFF4D966B),
              backgroundColor: const Color(0xFFE4EBE4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            '$value${suffix == null ? '' : ' • $suffix'}',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _MetricLine extends StatelessWidget {
  final String label;
  final String value;
  const _MetricLine(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF607069))),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _SpeciesMetricLine extends StatelessWidget {
  final String label;
  final String name;
  final String value;

  const _SpeciesMetricLine({
    required this.label,
    required this.name,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF607069))),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: name,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
                TextSpan(text: ' ($value)'),
              ],
            ),
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _InlineSpeciesStatistic extends StatelessWidget {
  final String label;
  final String name;
  final String value;

  const _InlineSpeciesStatistic({
    required this.label,
    required this.name,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '$label: '),
        TextSpan(
          text: name,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
        TextSpan(text: ' ($value)'),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Notice({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE8CB78)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF8B6514)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: Color(0xFF55420F))),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insights_outlined, size: 64, color: Color(0xFF4D966B)),
          SizedBox(height: 16),
          Text(
            'No insights yet',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(
            'Save your first fungi observation to begin building your personal detection statistics.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 56, color: Color(0xFFB23A2E)),
          const SizedBox(height: 12),
          const Text(
            'Insights could not be loaded',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your observations are unchanged. Please try again.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

int _rarityRank(SpeciesRarity value) => switch (value) {
  SpeciesRarity.veryRare => 4,
  SpeciesRarity.rare => 3,
  SpeciesRarity.uncommon => 2,
  SpeciesRarity.common => 1,
  SpeciesRarity.unknown => 0,
};
int _toxicityRank(ToxicityCategory value) => switch (value) {
  ToxicityCategory.deadly => 6,
  ToxicityCategory.poisonous => 5,
  ToxicityCategory.potentiallyPoisonous => 4,
  ToxicityCategory.causesGastrointestinalIllness => 3,
  ToxicityCategory.psychoactive => 2,
  ToxicityCategory.notKnownPoisonous => 1,
  ToxicityCategory.unknown => 0,
};
String _sortLabel(SpeciesInsightSort value) => switch (value) {
  SpeciesInsightSort.mostDetected => 'Most detected',
  SpeciesInsightSort.leastDetected => 'Least detected',
  SpeciesInsightSort.mostRecent => 'Most recent',
  SpeciesInsightSort.highestConfidence => 'Highest confidence',
  SpeciesInsightSort.rareSpecies => 'Rare species',
  SpeciesInsightSort.poisonousSpecies => 'Poisonous species',
  SpeciesInsightSort.alphabetical => 'Alphabetical',
};
String _rarityLabel(SpeciesRarity value) => switch (value) {
  SpeciesRarity.common => 'Common',
  SpeciesRarity.uncommon => 'Uncommon',
  SpeciesRarity.rare => 'Rare',
  SpeciesRarity.veryRare => 'Very rare',
  SpeciesRarity.unknown => 'Unknown',
};
String _toxicityLabel(ToxicityCategory value) => switch (value) {
  ToxicityCategory.deadly => 'Deadly',
  ToxicityCategory.poisonous => 'Poisonous',
  ToxicityCategory.potentiallyPoisonous => 'Potentially poisonous',
  ToxicityCategory.causesGastrointestinalIllness => 'May cause illness',
  ToxicityCategory.psychoactive => 'Psychoactive',
  ToxicityCategory.notKnownPoisonous => 'No known data',
  ToxicityCategory.unknown => 'Unknown',
};
String _sourceLabel(DetectionSourceCategory value) => switch (value) {
  DetectionSourceCategory.offline => 'Offline',
  DetectionSourceCategory.online => 'Online',
  DetectionSourceCategory.both => 'Both',
  DetectionSourceCategory.unknown => 'Unknown source',
};
String _percent(double? value) =>
    value == null ? 'Not available' : '${(value * 100).toStringAsFixed(1)}%';
String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
