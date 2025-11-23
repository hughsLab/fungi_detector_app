import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yaml/yaml.dart';

import 'native/native_yolo_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RealtimeDetectionApp());
}

class RealtimeDetectionApp extends StatelessWidget {
  const RealtimeDetectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Realtime Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DetectionPage(),
    );
  }
}

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
  List<String> _labels = [];
  bool _isInitialized = false;
  bool _hasPermission = false;

  int _inputWidth = 640;
  int _inputHeight = 640;
  late Size _previewSize;
  bool _isFrontCamera = false;

  List<Detection> _detections = [];
  String? _errorMessage;

  static const double _confThreshold = 0.30;
  static const double _nmsIoUThreshold = 0.45;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        final sortedKeys =
            namesNode.keys
                .where((k) => k is int || int.tryParse(k.toString()) != null)
                .map((k) => k is int ? k : int.parse(k.toString()))
                .toList()
              ..sort();
        names = sortedKeys.map((k) => namesNode[k].toString()).toList();
      }
    }

    if (names.isEmpty) {
      names = List.generate(80, (i) => 'class_$i');
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
    setState(() {
      _detections = detections
          .map(
            (d) => Detection(
              box: Rect.fromLTRB(d.left, d.top, d.right, d.bottom),
              score: d.score,
              classIndex: d.classIndex,
              label: _labelForIndex(d.classIndex),
            ),
          )
          .toList();
    });
  }

  String _labelForIndex(int index) {
    if (index >= 0 && index < _labels.length) {
      return _labels[index];
    }
    return 'id_$index';
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
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Realtime Detection')),
      body: _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : !_hasPermission
          ? const Center(child: CircularProgressIndicator())
          : !_isInitialized || _camera == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, _) {
                final preview = _camera!;

                return ColoredBox(
                  color: Colors.black,
                  child: SizedBox.expand(
                    child: ClipRect(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _previewSize.width,
                          height: _previewSize.height,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              SizedBox.expand(child: CameraPreview(preview)),
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
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class Detection {
  final Rect box;
  final double score;
  final int classIndex;
  final String label;

  Detection({
    required this.box,
    required this.score,
    required this.classIndex,
    required this.label,
  });
}

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final Size inputSize;
  final Size previewSize;
  final Size canvasSize;
  final bool isFrontCamera;

  DetectionPainter({
    required this.detections,
    required this.inputSize,
    required this.previewSize,
    required this.canvasSize,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.greenAccent;

    final Paint bgPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withValues(alpha: 0.5);

    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );

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
      canvas.drawRect(rect, boxPaint);

      final label = '${d.label} ${(d.score * 100).toStringAsFixed(1)}%';
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();

      final double textPadding = 4.0;
      final Rect textBgRect = Rect.fromLTWH(
        rect.left,
        math.max(0.0, rect.top - textPainter.height - 2),
        textPainter.width + textPadding * 2,
        textPainter.height + textPadding,
      );
      canvas.drawRect(textBgRect, bgPaint);
      textPainter.paint(
        canvas,
        Offset(textBgRect.left + textPadding, textBgRect.top + textPadding / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.canvasSize != canvasSize ||
        oldDelegate.isFrontCamera != isFrontCamera ||
        oldDelegate.previewSize != previewSize;
  }
}
