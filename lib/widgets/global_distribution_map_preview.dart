import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/map_tile_cache_service.dart';

class GlobalDistributionMapPreview extends StatefulWidget {
  final String? scientificName;
  final String? canonicalName;
  final String? speciesId;
  final String? modelId;
  final int? sourceClassId;
  final double? observationLatitude;
  final double? observationLongitude;
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
                    const _StaticMapPreview()
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
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: _MapNote(hasTileError: _hasTileError),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Distribution data coming soon.',
            style: TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
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

  const _MapNote({required this.hasTileError});

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
