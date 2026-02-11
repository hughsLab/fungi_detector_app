import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yaml/yaml.dart';

import '../detection/detection.dart';
import '../detection/stability_engine.dart';
import '../models/species.dart';
import '../models/navigation_args.dart';
import '../native/native_yolo_engine.dart';
import '../repositories/species_repository.dart';

const Color _deepGreen = Color(0xFF1F4E3D);
const Color _accentGreen = Color(0xFF8FBFA1);
const Color _highlightGreen = Color(0xFF7CD39A);
const Color _mutedWhite = Color(0xCCFFFFFF);

class DetectionPage extends StatefulWidget {
  const DetectionPage({super.key});

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage>
    with WidgetsBindingObserver {
  CameraController? _camera;
  NativeYoloEngine? _nativeEngine;
  StreamSubscription<List<NativeDetection>>? _nativeDetectionsSub;
  StreamSubscription<String>? _nativeErrorSub;
  late DetectionStabilityEngine _stabilityEngine;
  List<String> _labels = [];
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;
  Map<String, String> _speciesIdByName = {};
  Set<int> _lichenClassIndices = <int>{};
  Set<String> _lichenNames = <String>{};
  bool _isInitialized = false;
  bool _hasPermission = false;
  bool _engineReady = false;
  bool _isCapturing = false;

  int _inputWidth = 640;
  int _inputHeight = 640;
  late Size _previewSize;
  bool _isFrontCamera = false;

  List<Detection> _detections = [];
  StableTrack? _primaryTrack;
  String? _errorMessage;

  static const double _confThreshold = 0.30;
  static const double _nmsIoUThreshold = 0.45;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadSpeciesIndex());
    _initAll();
  }

  Future<void> _initAll() async {
    try {
      final permissionGranted = await _ensureCameraPermission();
      if (!permissionGranted) {
        setState(() {
          _errorMessage =
              'Camera permission is required for real-time detection. Please enable it in system settings and restart the app.';
        });
        return;
      }
      setState(() {
        _hasPermission = true;
      });
      _labels = await _loadClassNamesFromYaml('assets/models/metadata.yaml');
      debugPrint('labels.length: ${_labels.length}');
      _stabilityEngine = DetectionStabilityEngine(labels: _labels);
      _engineReady = true;
      await _initializeNativeEngine();
      await _initCamera();
      await _startImageStream();
    } catch (e, stack) {
      debugPrint('Initialization error: $e');
      debugPrintStack(stackTrace: stack);
      setState(() {
        _errorMessage = 'Failed to initialize detection: $e';
      });
    }
  }

  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted) {
      return true;
    }
    status = await Permission.camera.request();
    if (status.isGranted) {
      return true;
    }
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    return false;
  }

  Future<List<String>> _loadClassNamesFromYaml(String assetPath) async {
    final yamlStr = await rootBundle.loadString(assetPath);
    final doc = loadYaml(yamlStr);

    List<String> names = [];
    if (doc is YamlMap) {
      _updateInputShapeFromMetadata(doc);
      dynamic namesNode;
      if (doc.containsKey('names')) {
        namesNode = doc['names'];
      } else if (doc.containsKey('model') && doc['model'] is YamlMap) {
        final modelNode = doc['model'] as YamlMap;
        _updateInputShapeFromMetadata(modelNode);
        if (modelNode.containsKey('names')) {
          namesNode = modelNode['names'];
        }
      }

      if (namesNode is YamlList) {
        names = namesNode.map((e) => e.toString()).toList();
      } else if (namesNode is YamlMap) {
        final keys =
            namesNode.entries
                .map((entry) {
                  final key = entry.key;
                  if (key is int) {
                    return key;
                  }
                  return int.tryParse(key.toString());
                })
                .whereType<int>()
                .toList()
              ..sort();
        if (keys.isNotEmpty) {
          final int maxKey = keys.reduce(
            (value, element) => value > element ? value : element,
          );
          final filled = List<String>.filled(maxKey + 1, '');
          for (final entry in namesNode.entries) {
            final key = entry.key;
            final int? index = key is int ? key : int.tryParse(key.toString());
            if (index == null || index < 0 || index >= filled.length) {
              continue;
            }
            filled[index] = entry.value.toString();
          }
          names = filled;
        }
      }
    }

    if (names.isEmpty) {
      throw StateError('No class labels found in metadata');
    }
    if (names.any((name) => name.trim().isEmpty)) {
      throw StateError('Metadata labels contain empty entries');
    }
    return names;
  }

  void _updateInputShapeFromMetadata(YamlMap source) {
    final imgsz = source['imgsz'];
    if (imgsz is YamlList && imgsz.isNotEmpty) {
      if (imgsz.length >= 2 && imgsz[0] is num && imgsz[1] is num) {
        _inputWidth = (imgsz[0] as num).toInt();
        _inputHeight = (imgsz[1] as num).toInt();
      } else if (imgsz.length == 1 && imgsz[0] is num) {
        final size = (imgsz[0] as num).toInt();
        _inputWidth = size;
        _inputHeight = size;
      }
    }
  }

  Future<void> _initializeNativeEngine() async {
    final modelPath = await _materializeAsset(
      'assets/models/yolo11n_float32.tflite',
      'yolo11n_float32.tflite',
    );
    final config = NativeYoloConfig(
      modelPath: modelPath,
      inputWidth: _inputWidth,
      inputHeight: _inputHeight,
      threads: Platform.isAndroid ? 3 : 2,
      maxDetections: 150,
      confidenceThreshold: _confThreshold,
      iouThreshold: _nmsIoUThreshold,
      useGpu: true,
      allowFp16: true,
    );

    await _nativeDetectionsSub?.cancel();
    await _nativeErrorSub?.cancel();
    await _nativeEngine?.dispose();

    _nativeEngine = await NativeYoloEngine.create(config);
    _nativeDetectionsSub = _nativeEngine!.detections.listen(
      _onNativeDetections,
    );
    _nativeErrorSub = _nativeEngine!.errors.listen((msg) {
      debugPrint('Native engine warning: $msg');
    });
  }

  Future<String> _materializeAsset(String assetPath, String fileName) async {
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/$fileName');
    final data = await rootBundle.load(assetPath);
    if (!await file.exists() || (await file.length()) != data.lengthInBytes) {
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return file.path;
  }

  void _onNativeDetections(List<NativeDetection> detections) {
    if (!mounted) return;
    if (!_engineReady) return;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final List<Detection> mapped = detections
        .map(
          (d) => Detection(
            box: Rect.fromLTRB(d.left, d.top, d.right, d.bottom),
            confidence: d.score,
            classId: d.classIndex,
            label: _labelForIndex(d.classIndex),
          ),
        )
        .toList();
    final List<StableTrack> stableTracks = _stabilityEngine.processFrame(
      mapped,
      nowMs,
    );
    final StableTrack? primaryTrack = _selectPrimaryTrack(stableTracks);
    setState(() {
      _detections = mapped;
      _primaryTrack = primaryTrack;
    });
  }

  String _labelForIndex(int index) {
    if (index >= 0 && index < _labels.length) {
      final label = _labels[index].trim();
      if (label.isNotEmpty) {
        return label;
      }
    }
    return 'Unknown';
  }

  Future<void> _loadSpeciesIndex() async {
    try {
      final species = await _speciesRepository.loadSpecies();
      final map = <String, String>{};
      final lichenClassIndices = <int>{};
      final lichenNames = <String>{};
      for (final item in species) {
        final scientific = _normalizeName(item.scientificName);
        if (scientific.isNotEmpty) {
          map[scientific] = item.id;
        }
        final common = _normalizeName(item.commonName ?? '');
        if (common.isNotEmpty && !map.containsKey(common)) {
          map[common] = item.id;
        }
        if (_isLichenSpecies(item)) {
          final int? classIndex = int.tryParse(item.id);
          if (classIndex != null) {
            lichenClassIndices.add(classIndex);
          }
          if (scientific.isNotEmpty) {
            lichenNames.add(scientific);
          }
          if (common.isNotEmpty) {
            lichenNames.add(common);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _speciesIdByName = map;
        _lichenClassIndices = lichenClassIndices;
        _lichenNames = lichenNames;
      });
    } catch (e, stack) {
      debugPrint('Failed to load species index: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  bool _isLichenSpecies(Species species) {
    final String taxonomyClass = (species.taxonomyClass ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (taxonomyClass == 'lecanoromycetes') {
      return true;
    }

    final String combinedText = [
      species.commonName,
      species.shortDescription,
      species.taxonomyOrder,
      species.taxonomyFamily,
    ].whereType<String>().join(' ').toLowerCase();
    return combinedText.contains('lichen');
  }

  String _normalizeName(String value) {
    final normalized = value.trim().toLowerCase().replaceAll('_', ' ');
    return normalized.replaceAll(RegExp(r'\s+'), ' ');
  }

  String? _speciesIdForLabel(String label) {
    if (_speciesIdByName.isEmpty) {
      return null;
    }
    return _speciesIdByName[_normalizeName(label)];
  }

  bool _isLichenDetection({required int? classIndex, required String label}) {
    if (classIndex != null && _lichenClassIndices.contains(classIndex)) {
      return true;
    }
    final String normalizedLabel = _normalizeName(label);
    return _lichenNames.contains(normalizedLabel);
  }

  StableTrack? _selectPrimaryTrack(List<StableTrack> tracks) {
    if (tracks.isEmpty) {
      return null;
    }
    final List<StableTrack> locked = tracks
        .where((t) => t.lockedClassId != null)
        .toList();
    final List<StableTrack> candidates = locked.isNotEmpty ? locked : tracks;
    StableTrack best = candidates.first;
    double bestArea = best.bbox.width * best.bbox.height;
    for (final track in candidates.skip(1)) {
      final double area = track.bbox.width * track.bbox.height;
      if (area > bestArea) {
        best = track;
        bestArea = area;
      }
    }
    return best;
  }

  Future<void> _handleCapture(StableTrack track) async {
    if (_isCapturing) {
      return;
    }
    setState(() {
      _isCapturing = true;
    });

    String? photoPath;
    try {
      photoPath = await _capturePhoto();
      if (!mounted) return;

      final int? classIndex = track.lockedClassId ?? track.top1ClassId;
      final String label = classIndex == null
          ? 'Unknown'
          : _labelForIndex(classIndex);
      final bool isLichen = _isLichenDetection(
        classIndex: classIndex,
        label: label,
      );
      final String? speciesId = classIndex == null
          ? _speciesIdForLabel(label)
          : classIndex.toString();
      final args = DetectionResultArgs(
        lockedLabel: label,
        top2Label: track.isAmbiguous ? track.top2Label : null,
        top2ClassIndex: track.isAmbiguous ? track.top2ClassId : null,
        top1AvgConf: track.lockedClassId == null
            ? track.top1AvgConf
            : track.lockedAvgConf,
        top2AvgConf: track.isAmbiguous ? track.top2AvgConf : null,
        top1VoteRatio: track.top1VoteRatio,
        windowFrameCount: track.windowFrameCount,
        windowDurationMs: track.windowDurationMs,
        stabilityWinCount: track.stabilityWinCount,
        stabilityWindowSize: track.stabilityWindowSize,
        timestamp: DateTime.now(),
        speciesId: speciesId,
        classIndex: classIndex,
        photoPath: photoPath,
        isLichen: isLichen,
      );
      await Navigator.of(
        context,
      ).pushNamed('/detection-result', arguments: args);
    } finally {
      if (!mounted) return;
      try {
        if (_camera != null &&
            _camera!.value.isInitialized &&
            !_camera!.value.isStreamingImages) {
          await _startImageStream();
        }
      } catch (e, stack) {
        debugPrint('Failed to restart camera stream: $e');
        debugPrintStack(stackTrace: stack);
      }
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
      });
    }
  }

  Future<String?> _capturePhoto() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) {
      _showMessage('Camera not ready. Unable to capture photo.');
      return null;
    }

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      if (controller.value.isTakingPicture) {
        return null;
      }
      final XFile file = await controller.takePicture();
      return file.path;
    } catch (e, stack) {
      debugPrint('Photo capture error: $e');
      debugPrintStack(stackTrace: stack);
      _showMessage(
        'Could not capture photo. You can still save the observation.',
      );
      return null;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSpeciesDetail(String speciesId) {
    Navigator.of(context).pushNamed(
      '/species-detail',
      arguments: SpeciesDetailArgs(speciesId: speciesId),
    );
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final selected = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.isNotEmpty
          ? cameras.first
          : throw Exception('No camera found'),
    );

    if (_camera != null) {
      await _disposeCameraController(silently: true);
    }

    final controller = CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await controller.initialize();

    final pv = controller.value.previewSize!;
    final ui.FlutterView view =
        WidgetsBinding.instance.platformDispatcher.views.first;
    final orientation = MediaQueryData.fromView(view).orientation;
    final newPreviewSize = orientation == Orientation.portrait
        ? Size(pv.height, pv.width)
        : Size(pv.width, pv.height);

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _camera = controller;
      _isFrontCamera = selected.lensDirection == CameraLensDirection.front;
      _previewSize = newPreviewSize;
      _isInitialized = true;
    });
  }

  Future<void> _startImageStream() async {
    final controller = _camera;
    final engine = _nativeEngine;
    if (controller == null ||
        engine == null ||
        !controller.value.isInitialized) {
      return;
    }

    await controller.startImageStream((CameraImage image) {
      if (!mounted) return;
      final rotationDegrees = controller.description.sensorOrientation;
      engine.submitCameraImage(image, rotationDegrees: rotationDegrees);
    });
  }

  Future<void> _disposeCameraController({bool silently = false}) async {
    final controller = _camera;
    if (controller == null) {
      return;
    }

    try {
      if (controller.value.isInitialized &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}

    if (!silently && mounted) {
      setState(() {
        _camera = null;
        _isInitialized = false;
      });
    } else {
      _camera = null;
      _isInitialized = false;
    }

    try {
      await controller.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStreamAndDispose();
    super.dispose();
  }

  Future<void> _stopStreamAndDispose() async {
    await _disposeCameraController(silently: true);
    await _nativeDetectionsSub?.cancel();
    await _nativeErrorSub?.cancel();
    try {
      await _nativeEngine?.dispose();
    } catch (_) {}
    _nativeEngine = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_disposeCameraController());
    } else if (state == AppLifecycleState.resumed && _hasPermission) {
      _initCamera().then((_) => _startImageStream());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deepGreen,
      appBar: AppBar(
        title: const Text('Realtime Detection'),
        backgroundColor: _deepGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        actions: [
          IconButton(
            tooltip: 'Save Observation',
            icon: const Icon(Icons.bookmark_add),
            onPressed: () {
              Navigator.of(context).pushNamed('/save-observation');
            },
          ),
        ],
      ),
      body: _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 16, color: _mutedWhite),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : !_hasPermission
          ? const Center(child: CircularProgressIndicator(color: _accentGreen))
          : !_isInitialized || _camera == null
          ? const Center(child: CircularProgressIndicator(color: _accentGreen))
          : LayoutBuilder(
              builder: (context, _) {
                final preview = _camera!;
                final StableTrack? primaryTrack = _primaryTrack;
                final bool hasLocked = primaryTrack?.lockedClassId != null;
                final bool isAmbiguous = primaryTrack?.isAmbiguous ?? false;
                final bool isReady = primaryTrack?.isReadyToCapture ?? false;
                final String? primaryLabel = hasLocked
                    ? primaryTrack?.lockedLabel
                    : primaryTrack?.top1Label;
                final int? primaryClassIndex = hasLocked
                    ? primaryTrack?.lockedClassId
                    : primaryTrack?.top1ClassId;
                final String? topSpeciesId = primaryClassIndex == null
                    ? (primaryLabel == null
                          ? null
                          : _speciesIdForLabel(primaryLabel))
                    : primaryClassIndex.toString();
                final String? topConfidence = primaryTrack == null
                    ? null
                    : '${(primaryTrack.top1AvgConf * 100).toStringAsFixed(1)}%';
                final String statusText;
                final IconData statusIcon;
                if (primaryTrack == null) {
                  statusText = 'Scanning for species...';
                  statusIcon = Icons.center_focus_strong;
                } else if (isReady) {
                  statusText = 'Ready to capture';
                  statusIcon = Icons.check_circle;
                } else if (hasLocked) {
                  statusText = 'Stable detection - hold steady';
                  statusIcon = Icons.shield_outlined;
                } else {
                  statusText = 'Stabilising detection...';
                  statusIcon = Icons.timelapse;
                }

                String? bannerTitle;
                String? bannerSubtitle;
                String? bannerDetail;
                if (primaryTrack != null) {
                  if (hasLocked) {
                    bannerTitle = primaryTrack.lockedLabel;
                    if (isAmbiguous && primaryTrack.top2Label != null) {
                      bannerSubtitle =
                          'Also possible: ${primaryTrack.top2Label}';
                    } else if (topConfidence != null) {
                      bannerSubtitle = 'Stable $topConfidence';
                    }
                  } else {
                    bannerTitle = 'Stabilising...';
                    if (primaryTrack.top1Label != null) {
                      bannerSubtitle = 'Leading: ${primaryTrack.top1Label}';
                    }
                    if (isAmbiguous && primaryTrack.top2Label != null) {
                      bannerDetail = 'Also possible: ${primaryTrack.top2Label}';
                    }
                  }
                }

                return ColoredBox(
                  color: _deepGreen,
                  child: SizedBox.expand(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRect(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _previewSize.width,
                              height: _previewSize.height,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  SizedBox.expand(
                                    child: CameraPreview(preview),
                                  ),
                                  CustomPaint(
                                    painter: DetectionPainter(
                                      detections: _detections,
                                      inputSize: Size(
                                        _inputWidth.toDouble(),
                                        _inputHeight.toDouble(),
                                      ),
                                      previewSize: _previewSize,
                                      canvasSize: _previewSize,
                                      isFrontCamera: _isFrontCamera,
                                      accentColor: _accentGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    _deepGreen.withValues(alpha: 0.65),
                                    Colors.transparent,
                                    _deepGreen.withValues(alpha: 0.55),
                                  ],
                                  stops: const [0.0, 0.6, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Column(
                              children: [
                                if (bannerTitle != null)
                                  Align(
                                    alignment: Alignment.topCenter,
                                    child: _DetectionBanner(
                                      title: bannerTitle,
                                      subtitle: bannerSubtitle,
                                      secondarySubtitle: bannerDetail,
                                      accentColor: _accentGreen,
                                      backgroundColor: _deepGreen.withValues(
                                        alpha: 0.78,
                                      ),
                                      onTap: !hasLocked || topSpeciesId == null
                                          ? null
                                          : () => _openSpeciesDetail(
                                              topSpeciesId,
                                            ),
                                    ),
                                  ),
                                const Spacer(),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _StatusPill(
                                        text: statusText,
                                        icon: statusIcon,
                                        accentColor: isReady
                                            ? _highlightGreen
                                            : _accentGreen,
                                        backgroundColor: _deepGreen.withValues(
                                          alpha: 0.75,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        width: 220,
                                        child: ElevatedButton.icon(
                                          onPressed:
                                              (primaryTrack != null &&
                                                  isReady &&
                                                  !_isCapturing)
                                              ? () =>
                                                    _handleCapture(primaryTrack)
                                              : null,
                                          icon: const Icon(Icons.camera_alt),
                                          label: Text(
                                            _isCapturing
                                                ? 'Capturing...'
                                                : isReady
                                                ? 'Capture'
                                                : 'Not ready',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _highlightGreen,
                                            foregroundColor: _deepGreen,
                                            disabledBackgroundColor: _deepGreen
                                                .withValues(alpha: 0.35),
                                            disabledForegroundColor:
                                                _mutedWhite,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            shape: const StadiumBorder(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final Size inputSize;
  final Size previewSize;
  final Size canvasSize;
  final bool isFrontCamera;
  final Color accentColor;

  DetectionPainter({
    required this.detections,
    required this.inputSize,
    required this.previewSize,
    required this.canvasSize,
    required this.isFrontCamera,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..color = accentColor.withValues(alpha: 0.25);

    final Paint boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = accentColor;

    final double scaleXPreview = previewSize.width / inputSize.width;
    final double scaleYPreview = previewSize.height / inputSize.height;

    final double scaleXCanvas = canvasSize.width / previewSize.width;
    final double scaleYCanvas = canvasSize.height / previewSize.height;

    for (final d in detections) {
      double left = d.box.left * scaleXPreview;
      double top = d.box.top * scaleYPreview;
      double right = d.box.right * scaleXPreview;
      double bottom = d.box.bottom * scaleYPreview;

      if (isFrontCamera) {
        final double newLeft = previewSize.width - right;
        final double newRight = previewSize.width - left;
        left = newLeft;
        right = newRight;
      }

      left *= scaleXCanvas;
      right *= scaleXCanvas;
      top *= scaleYCanvas;
      bottom *= scaleYCanvas;

      final rect = Rect.fromLTRB(left, top, right, bottom);
      canvas.drawRect(rect, glowPaint);
      canvas.drawRect(rect, boxPaint);
    }
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.canvasSize != canvasSize ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isFrontCamera != isFrontCamera ||
        oldDelegate.previewSize != previewSize;
  }
}

class _DetectionBanner extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? secondarySubtitle;
  final Color accentColor;
  final Color backgroundColor;
  final VoidCallback? onTap;

  const _DetectionBanner({
    required this.title,
    required this.subtitle,
    required this.secondarySubtitle,
    required this.accentColor,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accentColor.withValues(alpha: 0.9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(color: _mutedWhite, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (secondarySubtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      secondarySubtitle!,
                      style: const TextStyle(color: _mutedWhite, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: card,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;

  const _StatusPill({
    required this.text,
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accentColor, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(color: _mutedWhite, fontSize: 12.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
