import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:yaml/yaml.dart';

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

class _DetectionPageState extends State<DetectionPage> with WidgetsBindingObserver {
  CameraController? _camera;
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isBusy = false;
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
      await _loadInterpreter('assets/models/yolo11n_float32.tflite');
      await _initCamera();

      setState(() {
        _isInitialized = true;
      });

      _dumpModelInfo();
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
      dynamic namesNode;
      if (doc.containsKey('names')) {
        namesNode = doc['names'];
      } else if (doc.containsKey('model') && doc['model'] is YamlMap) {
        final modelNode = doc['model'] as YamlMap;
        if (modelNode.containsKey('names')) {
          namesNode = modelNode['names'];
        }
      }

      if (namesNode is YamlList) {
        names = namesNode.map((e) => e.toString()).toList();
      } else if (namesNode is YamlMap) {
        final sortedKeys = namesNode.keys
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

  Future<void> _loadInterpreter(String assetPath) async {
    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(assetPath, options: options);

    final inputTensor = _interpreter!.getInputTensors().first;
    final shape = inputTensor.shape;
    if (shape.length == 4) {
      if (shape[3] == 3) {
        _inputHeight = shape[1];
        _inputWidth = shape[2];
      } else if (shape[1] == 3) {
        _inputHeight = shape[2];
        _inputWidth = shape[3];
      }
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    CameraDescription selected = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.isNotEmpty ? cameras.first : throw Exception('No camera found'),
    );

    _isFrontCamera = selected.lensDirection == CameraLensDirection.front;

    _camera = CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _camera!.initialize();

    final pv = _camera!.value.previewSize!;
    final ui.FlutterView view = WidgetsBinding.instance.platformDispatcher.views.first;
    final orientation = MediaQueryData.fromView(view).orientation;
    _previewSize = orientation == Orientation.portrait ? Size(pv.height, pv.width) : Size(pv.width, pv.height);
  }

  void _dumpModelInfo() {
    final inputs = _interpreter!.getInputTensors();
    final outputs = _interpreter!.getOutputTensors();

    debugPrint('Model Inputs:');
    for (final t in inputs) {
      debugPrint(' - name=${t.name}, shape=${t.shape}, type=${t.type}');
    }
    debugPrint('Model Outputs:');
    for (final t in outputs) {
      debugPrint(' - name=${t.name}, shape=${t.shape}, type=${t.type}');
    }
  }

  Future<void> _startImageStream() async {
    if (!(_camera?.value.isInitialized ?? false)) return;

    await _camera!.startImageStream((CameraImage image) async {
      if (_isBusy || !mounted || _interpreter == null) return;
      _isBusy = true;

      try {
        await _processCameraImage(image);
      } catch (e, stack) {
        debugPrint('Processing error: $e');
        debugPrintStack(stackTrace: stack);
      } finally {
        _isBusy = false;
      }
    });
  }

  Future<void> _processCameraImage(CameraImage camImage) async {
    final rgb = _convertYUV420ToImage(camImage);

    final rotationDegrees = _camera?.description.sensorOrientation ?? 0;
    imglib.Image oriented = rgb;
    if (rotationDegrees != 0) {
      oriented = imglib.copyRotate(rgb, rotationDegrees);
    }

    final inputBuffer = _preprocess(oriented, _inputWidth, _inputHeight);

    final outputTensor = _interpreter!.getOutputTensors().first;
    final outputShape = outputTensor.shape;
    final outputBuffer = Float32List(outputShape.reduce((value, element) => value * element));

    _interpreter!.run(
      inputBuffer.buffer.asUint8List(),
      outputBuffer.buffer.asUint8List(),
    );

    final detections = _decodeDetections(outputBuffer, outputShape, inputW: _inputWidth, inputH: _inputHeight);
    final filtered = _nonMaxSuppression(detections, iouThreshold: _nmsIoUThreshold);

    if (!mounted) return;
    setState(() {
      _detections = filtered;
    });
  }

  Float32List _preprocess(imglib.Image rgb, int targetW, int targetH) {
    final resized = imglib.copyResize(
      rgb,
      width: targetW,
      height: targetH,
      interpolation: imglib.Interpolation.linear,
    );
    final buffer = Float32List(targetW * targetH * 3);
    int index = 0;
    for (int y = 0; y < targetH; y++) {
      for (int x = 0; x < targetW; x++) {
        final pixel = resized.getPixel(x, y);
        buffer[index++] = imglib.getRed(pixel) / 255.0;
        buffer[index++] = imglib.getGreen(pixel) / 255.0;
        buffer[index++] = imglib.getBlue(pixel) / 255.0;
      }
    }
    return buffer;
  }

  List<Detection> _decodeDetections(
    Float32List output,
    List<int> shape, {
    required int inputW,
    required int inputH,
  }) {
    if (shape.length != 3 && shape.length != 4) {
      return [];
    }

    int numBoxes;
    int channels;
    bool channelsFirst;

    if (shape.length == 3) {
      final a = shape[1];
      final b = shape[2];
      if (a <= b && (a == 84 || a == 85 || (a > 4 && a < 200))) {
        channels = a;
        numBoxes = b;
        channelsFirst = true;
      } else {
        channels = b;
        numBoxes = a;
        channelsFirst = false;
      }
    } else {
      final a = shape[2];
      final b = shape[3];
      if (a == 84 || a == 85 || (a > 4 && a < 200)) {
        channels = a;
        numBoxes = b;
        channelsFirst = true;
      } else {
        channels = b;
        numBoxes = a;
        channelsFirst = false;
      }
    }

    final hasObjectness = (channels >= 85);
    final numClasses = hasObjectness ? channels - 5 : channels - 4;

    final List<Detection> results = [];
    for (int i = 0; i < numBoxes; i++) {
      double cx, cy, w, h, objectness = 1.0;
      int bestClass = -1;
      double bestScore = -double.infinity;

      if (channelsFirst) {
        final base = i;
        cx = output[0 * numBoxes + base];
        cy = output[1 * numBoxes + base];
        w = output[2 * numBoxes + base];
        h = output[3 * numBoxes + base];
        if (hasObjectness) {
          objectness = output[4 * numBoxes + base];
        }
        final classStart = hasObjectness ? 5 : 4;
        for (int c = 0; c < numClasses; c++) {
          final clsScore = output[(classStart + c) * numBoxes + base];
          if (clsScore > bestScore) {
            bestScore = clsScore;
            bestClass = c;
          }
        }
      } else {
        final base = i * channels;
        cx = output[base + 0];
        cy = output[base + 1];
        w = output[base + 2];
        h = output[base + 3];
        if (hasObjectness) {
          objectness = output[base + 4];
        }
        final classStart = hasObjectness ? 5 : 4;
        for (int c = 0; c < numClasses; c++) {
          final clsScore = output[base + classStart + c];
          if (clsScore > bestScore) {
            bestScore = clsScore;
            bestClass = c;
          }
        }
      }

      final score = hasObjectness ? (objectness * bestScore) : bestScore;
      if (score < _confThreshold) {
        continue;
      }

      final isNormalized = (cx.abs() <= 1.5 && cy.abs() <= 1.5 && w <= 1.5 && h <= 1.5);
      final double scaleX = isNormalized ? inputW.toDouble() : 1.0;
      final double scaleY = isNormalized ? inputH.toDouble() : 1.0;

      final double bx = cx * scaleX - (w * scaleX) / 2.0;
      final double by = cy * scaleY - (h * scaleY) / 2.0;
      final double bw = w * scaleX;
      final double bh = h * scaleY;

      final double left = bx.clamp(0.0, inputW.toDouble());
      final double top = by.clamp(0.0, inputH.toDouble());
      final double right = (bx + bw).clamp(0.0, inputW.toDouble());
      final double bottom = (by + bh).clamp(0.0, inputH.toDouble());

      results.add(
        Detection(
          box: Rect.fromLTRB(left, top, right, bottom),
          score: score,
          classIndex: bestClass,
          label: bestClass >= 0 && bestClass < _labels.length ? _labels[bestClass] : 'id_$bestClass',
        ),
      );
    }

    return results;
  }

  List<Detection> _nonMaxSuppression(List<Detection> detections, {double iouThreshold = 0.45}) {
    final dets = List<Detection>.from(detections)..sort((a, b) => b.score.compareTo(a.score));
    final List<Detection> keep = [];

    while (dets.isNotEmpty) {
      final best = dets.removeAt(0);
      keep.add(best);

      dets.removeWhere((d) {
        if (d.classIndex != best.classIndex) return false;
        final iou = _iou(best.box, d.box);
        return iou > iouThreshold;
      });
    }
    return keep;
  }

  double _iou(Rect a, Rect b) {
    final double interLeft = math.max(a.left, b.left);
    final double interTop = math.max(a.top, b.top);
    final double interRight = math.min(a.right, b.right);
    final double interBottom = math.min(a.bottom, b.bottom);

    final double interW = math.max(0.0, interRight - interLeft);
    final double interH = math.max(0.0, interBottom - interTop);
    final double interArea = interW * interH;

    final double areaA = (a.width) * (a.height);
    final double areaB = (b.width) * (b.height);

    final double union = areaA + areaB - interArea + 1e-5;
    return interArea / union;
  }

  imglib.Image _convertYUV420ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    final int yRowStride = yPlane.bytesPerRow;
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 2;

    final Uint8List yBytes = yPlane.bytes;
    final Uint8List uBytes = uPlane.bytes;
    final Uint8List vBytes = vPlane.bytes;

    final Uint8List rgbBytes = Uint8List(width * height * 3);

    int rgbIndex = 0;
    for (int y = 0; y < height; y++) {
      final int yRow = yRowStride * y;
      final int uvRow = uvRowStride * (y >> 1);

      for (int x = 0; x < width; x++) {
        final int yIndex = yRow + x;
        final int uvIndex = uvRow + (x >> 1) * uvPixelStride;

        final int yp = yBytes[yIndex] & 0xFF;
        final int up = uBytes[uvIndex] & 0xFF;
        final int vp = vBytes[uvIndex] & 0xFF;

        final double yf = yp.toDouble();
        final double uf = up.toDouble() - 128.0;
        final double vf = vp.toDouble() - 128.0;

        int r = (yf + 1.402 * vf).round();
        int g = (yf - 0.344136 * uf - 0.714136 * vf).round();
        int b = (yf + 1.772 * uf).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        rgbBytes[rgbIndex++] = r;
        rgbBytes[rgbIndex++] = g;
        rgbBytes[rgbIndex++] = b;
      }
    }

    return imglib.Image.fromBytes(width, height, rgbBytes, format: imglib.Format.rgb);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStreamAndDispose();
    super.dispose();
  }

  Future<void> _stopStreamAndDispose() async {
    try {
      if (_camera != null) {
        if (_camera!.value.isStreamingImages) {
          await _camera!.stopImageStream();
        }
        await _camera!.dispose();
      }
    } catch (_) {}
    try {
      _interpreter?.close();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? controller = _camera;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      controller.stopImageStream();
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera().then((_) => _startImageStream());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      builder: (context, constraints) {
                        final preview = _camera!;
                        final size = constraints.biggest;

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(preview),
                            CustomPaint(
                              painter: DetectionPainter(
                                detections: _detections,
                                inputSize: Size(_inputWidth.toDouble(), _inputHeight.toDouble()),
                                previewSize: _previewSize,
                                canvasSize: size,
                                isFrontCamera: _isFrontCamera,
                              ),
                            ),
                          ],
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
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
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
      textPainter.paint(canvas, Offset(textBgRect.left + textPadding, textBgRect.top + textPadding / 2));
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
