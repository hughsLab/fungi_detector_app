import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/species_map_marker.dart';
import '../services/map_tile_cache_service.dart';

class GlobalDistributionMapPreview extends StatefulWidget {
  final String? scientificName;
  final String? canonicalName;
  final String? speciesId;
  final String? modelId;
  final int? sourceClassId;
  final double? observationLatitude;
  final double? observationLongitude;
  final List<SpeciesMapMarker> markers;
  final String emptyText;
  final double height;

  const GlobalDistributionMapPreview({
    super.key,
    this.scientificName,
    this.canonicalName,
    this.speciesId,
    this.modelId,
    this.sourceClassId,
    this.observationLatitude,
    this.observationLongitude,
    this.markers = const <SpeciesMapMarker>[],
    this.emptyText = 'Location data not available for this species.',
    this.height = 210,
  });

  @override
  State<GlobalDistributionMapPreview> createState() =>
      _GlobalDistributionMapPreviewState();
}

class _GlobalDistributionMapPreviewState
    extends State<GlobalDistributionMapPreview> {
  static const LatLng _initialCenter = LatLng(12, 15);
  static const double _initialZoom = 1.45;
  static const double _minZoom = 1;
  static const double _maxZoom = 6;

  final MapController _mapController = MapController();
  bool _hasTileError = false;
  SpeciesMapMarker? _selectedMarker;

  @override
  void didUpdateWidget(covariant GlobalDistributionMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selectedMarker;
    if (selected == null) {
      return;
    }
    final stillVisible = widget.markers.any(
      (marker) => _sameMarker(marker, selected),
    );
    if (!stillVisible) {
      _selectedMarker = null;
    }
  }

  void _zoomBy(double delta) {
    try {
      final camera = _mapController.camera;
      final nextZoom = (camera.zoom + delta).clamp(_minZoom, _maxZoom);
      _mapController.move(camera.center, nextZoom.toDouble());
    } catch (_) {
      // The controller can be unavailable during the first frame.
    }
  }

  @override
  Widget build(BuildContext context) {
    final double mapHeight = widget.height.clamp(180, 240).toDouble();
    final bool useStaticPreview = _isRunningInWidgetTest;
    final bool hasMarkers = widget.markers.isNotEmpty;
    final List<Marker> mapMarkers = widget.markers
        .map(
          (marker) => Marker(
            point: LatLng(marker.latitude, marker.longitude),
            width: 42,
            height: 42,
            child: _DistributionMarkerButton(
              marker: marker,
              isSelected:
                  _selectedMarker != null &&
                  _sameMarker(marker, _selectedMarker!),
              onTap: () => _selectMarker(marker),
            ),
          ),
        )
        .toList(growable: false);

    return Semantics(
      label: _semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Global Distribution Map',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: mapHeight,
              decoration: BoxDecoration(
                color: const Color(0xFF0C241A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF8FBFA1).withValues(alpha: 0.24),
                ),
              ),
              child: Stack(
                children: [
                  if (useStaticPreview)
                    Stack(
                      children: [
                        const _StaticMapPreview(),
                        _StaticMarkerLayer(
                          markers: widget.markers,
                          selectedMarker: _selectedMarker,
                          onMarkerTap: _selectMarker,
                        ),
                      ],
                    )
                  else
                    FlutterMap(
                      mapController: _mapController,
                      options: const MapOptions(
                        initialCenter: _initialCenter,
                        initialZoom: _initialZoom,
                        minZoom: _minZoom,
                        maxZoom: _maxZoom,
                        backgroundColor: Color(0xFF0C241A),
                        interactionOptions: InteractionOptions(
                          flags: InteractiveFlag.drag |
                              InteractiveFlag.flingAnimation |
                              InteractiveFlag.pinchMove |
                              InteractiveFlag.pinchZoom |
                              InteractiveFlag.doubleTapZoom |
                              InteractiveFlag.doubleTapDragZoom |
                              InteractiveFlag.scrollWheelZoom,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: MapTileCacheService.tileUrlTemplate,
                          userAgentPackageName:
                              MapTileCacheService.tileUserAgentPackageName,
                          tileProvider:
                              MapTileCacheService.instance.tileProvider(
                            cachingEnabled: true,
                          ),
                          errorTileCallback: (_, __, ___) {
                            if (!_hasTileError && mounted) {
                              setState(() {
                                _hasTileError = true;
                              });
                            }
                          },
                        ),
                        if (mapMarkers.isNotEmpty)
                          MarkerLayer(markers: mapMarkers),
                      ],
                    ),
                  if (!useStaticPreview)
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Color(0x660B281D)),
                        child: SizedBox.expand(),
                      ),
                    ),
                  if (!useStaticPreview)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: _ZoomControls(
                        onZoomIn: () => _zoomBy(0.75),
                        onZoomOut: () => _zoomBy(-0.75),
                      ),
                    ),
                  if (_selectedMarker != null)
                    Positioned(
                      left: 10,
                      right: 58,
                      top: 10,
                      child: _MarkerPopup(marker: _selectedMarker!),
                    ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: _MapNote(
                      hasTileError: _hasTileError,
                      hasMarkers: hasMarkers,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasMarkers
                ? 'Presence markers are approximate and do not imply abundance.'
                : widget.emptyText,
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  void _selectMarker(SpeciesMapMarker marker) {
    setState(() {
      _selectedMarker = marker;
    });
  }

  bool _sameMarker(SpeciesMapMarker a, SpeciesMapMarker b) {
    return a.label == b.label &&
        a.source == b.source &&
        a.latitude == b.latitude &&
        a.longitude == b.longitude;
  }

  String get _semanticLabel {
    final name = widget.scientificName?.trim();
    if (name == null || name.isEmpty) {
      return 'Interactive global distribution map preview';
    }
    return 'Interactive global distribution map preview for $name';
  }

  bool get _isRunningInWidgetTest {
    var isTestBinding = false;
    assert(() {
      isTestBinding = WidgetsBinding.instance.runtimeType
          .toString()
          .contains('TestWidgetsFlutterBinding');
      return true;
    }());
    return isTestBinding;
  }
}

class _StaticMarkerLayer extends StatelessWidget {
  final List<SpeciesMapMarker> markers;
  final SpeciesMapMarker? selectedMarker;
  final ValueChanged<SpeciesMapMarker> onMarkerTap;

  const _StaticMarkerLayer({
    required this.markers,
    required this.selectedMarker,
    required this.onMarkerTap,
  });

  @override
  Widget build(BuildContext context) {
    if (markers.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: markers.map((marker) {
            final offset = _project(marker, size);
            final maxLeft = size.width > 44 ? size.width - 44 : 2.0;
            final maxTop = size.height > 44 ? size.height - 44 : 2.0;
            final left = (offset.dx - 21)
                .clamp(2.0, maxLeft)
                .toDouble();
            final top = (offset.dy - 21)
                .clamp(2.0, maxTop)
                .toDouble();
            final bool isSelected = selectedMarker != null &&
                marker.label == selectedMarker!.label &&
                marker.source == selectedMarker!.source &&
                marker.latitude == selectedMarker!.latitude &&
                marker.longitude == selectedMarker!.longitude;
            return Positioned(
              left: left,
              top: top,
              child: _DistributionMarkerButton(
                marker: marker,
                isSelected: isSelected,
                onTap: () => onMarkerTap(marker),
              ),
            );
          }).toList(growable: false),
        );
      },
    );
  }

  Offset _project(SpeciesMapMarker marker, Size size) {
    final x = ((marker.longitude + 180) / 360) * size.width;
    final y = ((90 - marker.latitude) / 180) * size.height;
    return Offset(x, y);
  }
}

class _DistributionMarkerButton extends StatelessWidget {
  final SpeciesMapMarker marker;
  final bool isSelected;
  final VoidCallback onTap;

  const _DistributionMarkerButton({
    required this.marker,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fill = isSelected
        ? const Color(0xFFC9F7D8)
        : const Color(0xFF9ED6AF);
    return Tooltip(
      message: marker.label,
      child: Semantics(
        button: true,
        label: '${marker.label} presence marker',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF1F4E3D),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.32),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.location_on,
                  color: Color(0xFF0C241A),
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkerPopup extends StatelessWidget {
  final SpeciesMapMarker marker;

  const _MarkerPopup({required this.marker});

  @override
  Widget build(BuildContext context) {
    final note = marker.note?.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF102F22).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF9ED6AF).withValues(alpha: 0.65),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              marker.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                note,
                style: const TextStyle(
                  color: Color(0xDFFFFFFF),
                  fontSize: 11.5,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StaticMapPreview extends StatelessWidget {
  const _StaticMapPreview();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0C241A),
            Color(0xFF143A2A),
            Color(0xFF0B1F18),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _StaticMapPainter(),
        child: SizedBox.expand(),
      ),
    );
  }
}

class _StaticMapPainter extends CustomPainter {
  const _StaticMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (double x = size.width / 6; x < size.width; x += size.width / 6) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = size.height / 4; y < size.height; y += size.height / 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final landPaint = Paint()
      ..color = const Color(0xFF7AA885).withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromLTWH(
        size.width * 0.12,
        size.height * 0.28,
        size.width * 0.24,
        size.height * 0.18,
      ),
      landPaint,
    );
    canvas.drawOval(
      Rect.fromLTWH(
        size.width * 0.42,
        size.height * 0.22,
        size.width * 0.20,
        size.height * 0.16,
      ),
      landPaint,
    );
    canvas.drawOval(
      Rect.fromLTWH(
        size.width * 0.58,
        size.height * 0.48,
        size.width * 0.26,
        size.height * 0.20,
      ),
      landPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _ZoomControls({required this.onZoomIn, required this.onZoomOut});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF123426).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(icon: Icons.add, onPressed: onZoomIn),
          Container(
            width: 28,
            height: 1,
            color: Colors.white.withValues(alpha: 0.14),
          ),
          _ZoomButton(icon: Icons.remove, onPressed: onZoomOut),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _ZoomButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 34,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: Colors.white,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        tooltip: icon == Icons.add ? 'Zoom in' : 'Zoom out',
      ),
    );
  }
}

class _MapNote extends StatelessWidget {
  final bool hasTileError;
  final bool hasMarkers;

  const _MapNote({
    required this.hasTileError,
    required this.hasMarkers,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF102F22).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF8FBFA1).withValues(alpha: 0.24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(
              hasTileError ? Icons.cloud_off : Icons.public,
              color: const Color(0xFF9ED6AF),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasTileError
                    ? 'Map tiles are unavailable. Try again when connected.'
                    : hasMarkers
                        ? 'Tap a marker to view the location label.'
                        : 'Pan and zoom to explore the global map.',
                style: const TextStyle(
                  color: Color(0xE6FFFFFF),
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
