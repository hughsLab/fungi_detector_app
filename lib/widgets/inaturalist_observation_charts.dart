import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/inaturalist_observation_histogram.dart';
import '../models/inaturalist_taxon.dart';
import '../services/inaturalist_service.dart';

class INaturalistObservationCharts extends StatefulWidget {
  final int? taxonId;
  final String scientificName;
  final INaturalistService? service;

  const INaturalistObservationCharts({
    super.key,
    required this.taxonId,
    required this.scientificName,
    this.service,
  });

  @override
  State<INaturalistObservationCharts> createState() =>
      _INaturalistObservationChartsState();
}

class _INaturalistObservationChartsState
    extends State<INaturalistObservationCharts> {
  late Future<INaturalistObservationHistogram?> _future;

  INaturalistService get _service =>
      widget.service ?? INaturalistService.instance;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant INaturalistObservationCharts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taxonId != widget.taxonId ||
        oldWidget.scientificName != widget.scientificName) {
      _future = _load();
    }
  }

  Future<INaturalistObservationHistogram?> _load() async {
    var taxonId = widget.taxonId;
    if (taxonId == null && widget.scientificName.trim().isNotEmpty) {
      final match = await _service.findTaxonByScientificName(
        widget.scientificName,
      );
      if (match.status == INaturalistMatchStatus.matched) {
        taxonId = match.taxonId;
      }
    }
    return taxonId == null
        ? null
        : _service.getObservationHistogramForTaxon(taxonId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<INaturalistObservationHistogram?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _ChartShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Public observation charts',
                  style: _headingStyle,
                ),
                SizedBox(height: 12),
                LinearProgressIndicator(),
              ],
            ),
          );
        }
        final histogram = snapshot.data;
        if (histogram == null ||
            (histogram.observationsByMonth.isEmpty &&
                histogram.observationsByYear.isEmpty)) {
          return const _ChartShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Public observation charts', style: _headingStyle),
                SizedBox(height: 6),
                Text(
                  'iNaturalist seasonal and history data are unavailable.',
                  style: _bodyStyle,
                ),
              ],
            ),
          );
        }
        final seasonal = List.generate(
          12,
          (index) => _ChartPoint(
            label: _monthLabels[index],
            value: histogram.observationsByMonth[index + 1] ?? 0,
          ),
        );
        final years = histogram.observationsByYear.keys.toList()..sort();
        final recentYears = years.length <= 12
            ? years
            : years.sublist(years.length - 12);
        final history = recentYears
            .map(
              (year) => _ChartPoint(
                label: '$year',
                value: histogram.observationsByYear[year] ?? 0,
              ),
            )
            .toList();
        return _ChartShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Public observation charts', style: _headingStyle),
              const SizedBox(height: 4),
              const Text(
                'Public iNaturalist records for this taxon',
                style: _bodyStyle,
              ),
              const SizedBox(height: 16),
              _HistogramChart(
                title: 'Seasonal observations',
                points: seasonal,
                semanticsPrefix: 'iNaturalist observations',
                showEveryLabel: true,
              ),
              const SizedBox(height: 20),
              _HistogramChart(
                title: 'Observation history',
                points: history,
                semanticsPrefix: 'iNaturalist observations',
              ),
              const SizedBox(height: 10),
              const Text(
                'Counts show reporting activity on iNaturalist and do not '
                'necessarily represent abundance or biological rarity.',
                style: TextStyle(
                  color: Color(0xBFFFFFFF),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChartShell extends StatelessWidget {
  final Widget child;
  const _ChartShell({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
    ),
    child: child,
  );
}

class _ChartPoint {
  final String label;
  final int value;
  const _ChartPoint({required this.label, required this.value});
}

class _HistogramChart extends StatefulWidget {
  final String title;
  final List<_ChartPoint> points;
  final String semanticsPrefix;
  final bool showEveryLabel;

  const _HistogramChart({
    required this.title,
    required this.points,
    required this.semanticsPrefix,
    this.showEveryLabel = false,
  });

  @override
  State<_HistogramChart> createState() => _HistogramChartState();
}

class _HistogramChartState extends State<_HistogramChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) {
      return Text('${widget.title}: no data', style: _bodyStyle);
    }
    final selected = _selectedIndex == null
        ? points.reduce((a, b) => a.value >= b.value ? a : b)
        : points[_selectedIndex!.clamp(0, points.length - 1)];
    return Semantics(
      label: points
          .map(
            (point) =>
                '${widget.semanticsPrefix}, ${point.label}, ${point.value}',
          )
          .join('. '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '${selected.label}: ${_formatCount(selected.value)}',
                style: const TextStyle(
                  color: Color(0xFFB7E17A),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                const leftPadding = 36.0;
                const rightPadding = 8.0;
                final chartWidth = math.max(
                  1,
                  constraints.maxWidth - leftPadding - rightPadding,
                );
                final fraction =
                    ((details.localPosition.dx - leftPadding) / chartWidth)
                        .clamp(0.0, 1.0);
                setState(() {
                  _selectedIndex =
                      (fraction * (points.length - 1)).round();
                });
              },
              child: SizedBox(
                height: 172,
                width: double.infinity,
                child: CustomPaint(
                  painter: _HistogramPainter(
                    points: points,
                    selectedIndex: _selectedIndex,
                    showEveryLabel: widget.showEveryLabel,
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

class _HistogramPainter extends CustomPainter {
  final List<_ChartPoint> points;
  final int? selectedIndex;
  final bool showEveryLabel;

  const _HistogramPainter({
    required this.points,
    required this.selectedIndex,
    required this.showEveryLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0;
    const right = 8.0;
    const top = 8.0;
    const bottom = 27.0;
    final width = math.max(1, size.width - left - right);
    final height = math.max(1, size.height - top - bottom);
    final maximum = math.max(1, points.map((item) => item.value).reduce(math.max));

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final axisStyle = const TextStyle(color: Color(0xBFFFFFFF), fontSize: 9);
    for (var row = 0; row <= 4; row++) {
      final y = top + height * row / 4;
      canvas.drawLine(Offset(left, y), Offset(left + width, y), gridPaint);
      _paintText(
        canvas,
        _formatCount((maximum * (4 - row) / 4).round()),
        Offset(0, y - 6),
        axisStyle,
        maxWidth: left - 4,
        align: TextAlign.right,
      );
    }

    final offsets = <Offset>[];
    for (var index = 0; index < points.length; index++) {
      final x = points.length == 1
          ? left + width / 2
          : left + width * index / (points.length - 1);
      final y = top + height * (1 - points[index].value / maximum);
      offsets.add(Offset(x, y));
      final showLabel = showEveryLabel ||
          index == 0 ||
          index == points.length - 1 ||
          index % math.max(1, (points.length / 4).round()) == 0;
      if (showLabel) {
        _paintText(
          canvas,
          points[index].label,
          Offset(x - 18, top + height + 7),
          axisStyle,
          maxWidth: 36,
          align: TextAlign.center,
        );
      }
    }

    final fillPath = Path()..moveTo(offsets.first.dx, top + height);
    for (final offset in offsets) {
      fillPath.lineTo(offset.dx, offset.dy);
    }
    fillPath
      ..lineTo(offsets.last.dx, top + height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = const Color(0xFF9BC34A).withValues(alpha: 0.2),
    );

    final linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final offset in offsets.skip(1)) {
      linePath.lineTo(offset.dx, offset.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = const Color(0xFF9BC34A)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (var index = 0; index < offsets.length; index++) {
      final selected = selectedIndex == index;
      canvas.drawCircle(
        offsets[index],
        selected ? 5 : 3,
        Paint()..color = selected ? Colors.white : const Color(0xFF75A900),
      );
      if (selected) {
        canvas.drawCircle(
          offsets[index],
          3,
          Paint()..color = const Color(0xFF75A900),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.showEveryLabel != showEveryLabel;
}

void _paintText(
  Canvas canvas,
  String text,
  Offset offset,
  TextStyle style, {
  required double maxWidth,
  TextAlign align = TextAlign.left,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: 1,
  )..layout(maxWidth: maxWidth);
  painter.paint(canvas, offset);
}

String _formatCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}K';
  }
  return '$value';
}

const _headingStyle = TextStyle(
  color: Colors.white,
  fontSize: 16,
  fontWeight: FontWeight.w700,
);
const _bodyStyle = TextStyle(color: Color(0xCCFFFFFF), height: 1.35);
const _monthLabels = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
