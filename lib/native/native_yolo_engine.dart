import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

class NativeYuvFrame {
  NativeYuvFrame({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
  });

  final int width;
  final int height;
  final int rotationDegrees;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;

  factory NativeYuvFrame.fromCameraImage(
    CameraImage image, {
    required int rotationDegrees,
  }) {
    if (image.planes.length < 3) {
      throw ArgumentError('Expected YUV420 image with 3 planes');
    }
    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    return NativeYuvFrame(
      width: image.width,
      height: image.height,
      rotationDegrees: rotationDegrees,
      yRowStride: yPlane.bytesPerRow,
      uvRowStride: uPlane.bytesPerRow,
      uvPixelStride: uPlane.bytesPerPixel ?? 2,
      yBytes: Uint8List.fromList(yPlane.bytes),
      uBytes: Uint8List.fromList(uPlane.bytes),
      vBytes: Uint8List.fromList(vPlane.bytes),
    );
  }
}

class NativeDetection {
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double score;
  final int classIndex;

  const NativeDetection({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.score,
    required this.classIndex,
  });

  factory NativeDetection.fromMap(Map<dynamic, dynamic> data) {
    return NativeDetection(
      left: (data['left'] as num).toDouble(),
      top: (data['top'] as num).toDouble(),
      right: (data['right'] as num).toDouble(),
      bottom: (data['bottom'] as num).toDouble(),
      score: (data['score'] as num).toDouble(),
      classIndex: data['classIndex'] as int,
    );
  }
}

class NativeYoloFrameResult {
  final List<NativeDetection> detections;
  final int frameId;
  final int? receivedAtMs;
  final int? workerMs;
  final int rawDetectionCount;
  final int filteredDetectionCount;
  final int? topRawClassId;
  final double? topRawConfidence;
  final double? topRejectedConfidence;
  final double displayConfidenceThreshold;

  const NativeYoloFrameResult({
    required this.detections,
    required this.frameId,
    required this.receivedAtMs,
    required this.workerMs,
    required this.rawDetectionCount,
    required this.filteredDetectionCount,
    required this.topRawClassId,
    required this.topRawConfidence,
    required this.topRejectedConfidence,
    required this.displayConfidenceThreshold,
  });
}

class NativeYoloConfig {
  final String modelPath;
  final String debugLabel;
  final int inputWidth;
  final int inputHeight;
  final int threads;
  final int maxDetections;
  final double confidenceThreshold;
  final double iouThreshold;
  final double displayConfidenceThreshold;
  final bool useGpu;
  final bool allowFp16;

  const NativeYoloConfig({
    required this.modelPath,
    this.debugLabel = 'native-yolo',
    required this.inputWidth,
    required this.inputHeight,
    this.threads = 2,
    this.maxDetections = 100,
    this.confidenceThreshold = 0.25,
    this.iouThreshold = 0.45,
    this.displayConfidenceThreshold = 0.45,
    this.useGpu = false,
    this.allowFp16 = true,
  });

  Map<String, dynamic> toMessage() {
    return <String, dynamic>{
      'modelPath': modelPath,
      'debugLabel': debugLabel,
      'inputWidth': inputWidth,
      'inputHeight': inputHeight,
      'threads': threads,
      'maxDetections': maxDetections,
      'confidenceThreshold': confidenceThreshold,
      'iouThreshold': iouThreshold,
      'displayConfidenceThreshold': displayConfidenceThreshold,
      'useGpu': useGpu,
      'allowFp16': allowFp16,
    };
  }
}

class NativeYoloEngine {
  NativeYoloEngine._({
    required SendPort workerSendPort,
    required StreamSubscription<dynamic> subscription,
    required Isolate isolate,
    required double displayConfidenceThreshold,
    required String debugLabel,
  })  : _workerSendPort = workerSendPort,
        _subscription = subscription,
        _isolate = isolate,
        _displayConfidenceThreshold = displayConfidenceThreshold,
        _debugLabel = debugLabel;

  final SendPort _workerSendPort;
  final StreamSubscription<dynamic> _subscription;
  final Isolate _isolate;
  final double _displayConfidenceThreshold;
  final String _debugLabel;

  final StreamController<List<NativeDetection>> _detectionsController = StreamController.broadcast();
  final StreamController<NativeYoloFrameResult> _frameResultsController = StreamController.broadcast();
  final StreamController<String> _errorsController = StreamController.broadcast();
  final Completer<void> _readyCompleter = Completer<void>();
  final Completer<void> _disposedCompleter = Completer<void>();

  bool _disposed = false;
  bool _frameInFlight = false;
  _FramePacket? _pendingFrame;
  Completer<List<NativeDetection>>? _singleDetectionCompleter;
  int _nextFrameId = 1;
  int _receivedFrameCount = 0;
  int _processedFrameCount = 0;
  int _droppedPendingFrameCount = 0;
  int _lastDebugLogMs = 0;
  int? _inFlightFrameId;
  int? _inFlightDispatchAtMs;

  Stream<List<NativeDetection>> get detections => _detectionsController.stream;
  Stream<NativeYoloFrameResult> get frameResults => _frameResultsController.stream;
  Stream<String> get errors => _errorsController.stream;
  Future<void> get ready => _readyCompleter.future;

  static Future<NativeYoloEngine> create(NativeYoloConfig config) async {
    final receivePort = ReceivePort();
    final sendPortCompleter = Completer<SendPort>();
    NativeYoloEngine? engine;

    late final StreamSubscription<dynamic> subscription;
    subscription = receivePort.listen((dynamic message) {
      if (message is SendPort) {
        if (!sendPortCompleter.isCompleted) {
          sendPortCompleter.complete(message);
        }
        return;
      }
      engine?._handleWorkerMessage(message);
    });

    final isolate = await Isolate.spawn(
      _nativeYoloIsolateEntry,
      {
        'sendPort': receivePort.sendPort,
        'config': config.toMessage(),
      },
      debugName: 'native-yolo-engine',
    );

    final workerSendPort = await sendPortCompleter.future;
    engine = NativeYoloEngine._(
      workerSendPort: workerSendPort,
      subscription: subscription,
      isolate: isolate,
      displayConfidenceThreshold: config.displayConfidenceThreshold,
      debugLabel: config.debugLabel,
    );

    await engine.ready;
    return engine;
  }

  void submitCameraImage(CameraImage image, {required int rotationDegrees}) {
    submitFrame(
      NativeYuvFrame.fromCameraImage(
        image,
        rotationDegrees: rotationDegrees,
      ),
    );
  }

  void submitFrame(NativeYuvFrame frame) {
    if (_disposed) return;
    try {
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      _receivedFrameCount += 1;
      final packet = _FramePacket.fromNativeFrame(
        frame,
        frameId: _nextFrameId++,
        receivedAtMs: nowMs,
      );
      if (_pendingFrame != null) {
        _droppedPendingFrameCount += 1;
      }
      _pendingFrame?.dispose();
      _pendingFrame = packet;
      _debugLogFrame('received', frameId: packet.frameId);
      _pushPendingFrame();
    } catch (e) {
      _errorsController.add('Frame drop: $e');
    }
  }

  Future<List<NativeDetection>> detectFrame(
    NativeYuvFrame frame, {
    Duration timeout = const Duration(seconds: 4),
  }) {
    if (_disposed) {
      throw StateError('Native engine disposed');
    }
    if (_singleDetectionCompleter != null) {
      throw StateError('Native engine already has a pending one-shot request');
    }
    final completer = Completer<List<NativeDetection>>();
    _singleDetectionCompleter = completer;
    submitFrame(frame);
    return completer.future.timeout(timeout).whenComplete(() {
      if (_singleDetectionCompleter == completer) {
        _singleDetectionCompleter = null;
      }
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pendingFrame?.dispose();
    _pendingFrame = null;
    try {
      _workerSendPort.send({'type': 'dispose'});
      await _disposedCompleter.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Ignore and force-stop isolate.
    }
    await _subscription.cancel();
    _isolate.kill(priority: Isolate.immediate);
    await _frameResultsController.close();
    await _detectionsController.close();
    await _errorsController.close();
  }

  void _pushPendingFrame() {
    if (_disposed || _frameInFlight || _pendingFrame == null) {
      return;
    }
    final packet = _pendingFrame!;
    _pendingFrame = null;
    _frameInFlight = true;
    _inFlightFrameId = packet.frameId;
    _inFlightDispatchAtMs = DateTime.now().millisecondsSinceEpoch;
    _debugLogFrame(
      'submitted',
      frameId: packet.frameId,
      receivedAtMs: packet.receivedAtMs,
    );
    _workerSendPort.send({
      'type': 'frame',
      'frame': packet.serialize(),
    });
  }

  void _handleWorkerMessage(dynamic message) {
    if (_disposed) return;
    if (message is! Map) return;
    final type = message['type'] as String?;
    switch (type) {
      case 'ready':
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.complete();
        }
        break;
      case 'detections':
        final int nowMs = DateTime.now().millisecondsSinceEpoch;
        final items = (message['items'] as List<dynamic>)
            .map((dynamic e) => NativeDetection.fromMap(e as Map<dynamic, dynamic>))
            .toList(growable: false);
        final filtered = items
            .where((d) => d.score >= _displayConfidenceThreshold)
            .toList(growable: false);
        NativeDetection? topRaw;
        NativeDetection? topRejected;
        for (final item in items) {
          if (topRaw == null || item.score > topRaw.score) {
            topRaw = item;
          }
          if (item.score < _displayConfidenceThreshold &&
              (topRejected == null || item.score > topRejected.score)) {
            topRejected = item;
          }
        }
        final oneShot = _singleDetectionCompleter;
        if (oneShot != null && !oneShot.isCompleted) {
          oneShot.complete(filtered);
          _singleDetectionCompleter = null;
        }
        final int? frameId = message['frameId'] as int?;
        final int? receivedAtMs = message['receivedAtMs'] as int?;
        final int? workerMs = message['workerMs'] as int?;
        _frameResultsController.add(
          NativeYoloFrameResult(
            detections: filtered,
            frameId: frameId ?? -1,
            receivedAtMs: receivedAtMs,
            workerMs: workerMs,
            rawDetectionCount: items.length,
            filteredDetectionCount: filtered.length,
            topRawClassId: topRaw?.classIndex,
            topRawConfidence: topRaw?.score,
            topRejectedConfidence: topRejected?.score,
            displayConfidenceThreshold: _displayConfidenceThreshold,
          ),
        );
        _detectionsController.add(filtered);
        _processedFrameCount += 1;
        final int? dispatchMs = _inFlightDispatchAtMs;
        _debugLogFrame(
          'returned',
          frameId: frameId,
          receivedAtMs: receivedAtMs,
          workerMs: workerMs,
          inFlightMs: dispatchMs == null ? null : nowMs - dispatchMs,
          detectionCount: filtered.length,
          rawDetectionCount: items.length,
        );
        _frameInFlight = false;
        _inFlightFrameId = null;
        _inFlightDispatchAtMs = null;
        _pushPendingFrame();
        break;
      case 'error':
        final error = (message['message'] ?? 'Native engine error') as String;
        final oneShot = _singleDetectionCompleter;
        if (oneShot != null && !oneShot.isCompleted) {
          oneShot.completeError(Exception(error));
          _singleDetectionCompleter = null;
        }
        _errorsController.add(error);
        _frameInFlight = false;
        _inFlightFrameId = null;
        _inFlightDispatchAtMs = null;
        _pushPendingFrame();
        if (!(message['recoverable'] as bool? ?? true) && !_readyCompleter.isCompleted) {
          _readyCompleter.completeError(Exception(error));
        }
        break;
      case 'disposed':
        if (!_disposedCompleter.isCompleted) {
          _disposedCompleter.complete();
        }
        break;
      default:
        break;
    }
  }

  void _debugLogFrame(
    String event, {
    int? frameId,
    int? receivedAtMs,
    int? workerMs,
    int? inFlightMs,
    int? detectionCount,
    int? rawDetectionCount,
  }) {
    if (!kDebugMode) {
      return;
    }
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final bool shouldLogSummary = nowMs - _lastDebugLogMs >= 1200;
    final bool shouldLogEvent = event != 'received';
    if (!shouldLogSummary && !shouldLogEvent) {
      return;
    }
    if (shouldLogSummary) {
      _lastDebugLogMs = nowMs;
    }
    final StringBuffer out =
        StringBuffer('[DetectTiming][engine][$_debugLabel] $event');
    if (frameId != null) {
      out.write(' frame=$frameId');
    } else if (_inFlightFrameId != null) {
      out.write(' frame=$_inFlightFrameId');
    }
    if (receivedAtMs != null) {
      out.write(' queueMs=${nowMs - receivedAtMs}');
    }
    if (inFlightMs != null) {
      out.write(' roundTripMs=$inFlightMs');
    }
    if (workerMs != null) {
      out.write(' workerMs=$workerMs');
    }
    if (detectionCount != null) {
      out.write(' dets=$detectionCount');
    }
    if (rawDetectionCount != null) {
      out.write(' rawDets=$rawDetectionCount');
    }
    if (shouldLogSummary) {
      out.write(
        ' stats(received=$_receivedFrameCount processed=$_processedFrameCount droppedPending=$_droppedPendingFrameCount)',
      );
    }
    debugPrint(out.toString());
  }
}

class _FramePacket {
  _FramePacket({
    required this.width,
    required this.height,
    required this.frameId,
    required this.receivedAtMs,
    required this.rotationDegrees,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.yData,
    required this.uData,
    required this.vData,
  });

  final int width;
  final int height;
  final int frameId;
  final int receivedAtMs;
  final int rotationDegrees;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final TransferableTypedData yData;
  final TransferableTypedData uData;
  final TransferableTypedData vData;

  factory _FramePacket.fromNativeFrame(
    NativeYuvFrame frame, {
    required int frameId,
    required int receivedAtMs,
  }) {
    return _FramePacket(
      width: frame.width,
      height: frame.height,
      frameId: frameId,
      receivedAtMs: receivedAtMs,
      rotationDegrees: frame.rotationDegrees,
      yRowStride: frame.yRowStride,
      uvRowStride: frame.uvRowStride,
      uvPixelStride: frame.uvPixelStride,
      yData: TransferableTypedData.fromList([frame.yBytes]),
      uData: TransferableTypedData.fromList([frame.uBytes]),
      vData: TransferableTypedData.fromList([frame.vBytes]),
    );
  }

  Map<String, dynamic> serialize() {
    return <String, dynamic>{
      'width': width,
      'height': height,
      'frameId': frameId,
      'receivedAtMs': receivedAtMs,
      'rotation': rotationDegrees,
      'yRowStride': yRowStride,
      'uvRowStride': uvRowStride,
      'uvPixelStride': uvPixelStride,
      'yData': yData,
      'uData': uData,
      'vData': vData,
    };
  }

  void dispose() {}
}

void _nativeYoloIsolateEntry(Map<String, dynamic> message) async {
  final SendPort mainPort = message['sendPort'] as SendPort;
  final Map<String, dynamic> config = (message['config'] as Map<dynamic, dynamic>).cast<String, dynamic>();

  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);
  final worker = _NativeYoloWorker(config);
  try {
    await worker.initialize();
    mainPort.send({'type': 'ready'});
  } catch (e) {
    mainPort.send({'type': 'error', 'message': 'Native init failed: $e', 'recoverable': false});
    return;
  }

  await for (final dynamic raw in receivePort) {
    if (raw is! Map) {
      continue;
    }
    final type = raw['type'] as String?;
    if (type == 'frame') {
      final frameMap = (raw['frame'] as Map<dynamic, dynamic>).cast<String, dynamic>();
      try {
        final Stopwatch sw = Stopwatch()..start();
        final detections = worker.processFrame(frameMap);
        sw.stop();
        mainPort.send({
          'type': 'detections',
          'items': detections,
          'frameId': frameMap['frameId'],
          'receivedAtMs': frameMap['receivedAtMs'],
          'workerMs': sw.elapsedMilliseconds,
        });
      } catch (e) {
        mainPort.send({'type': 'error', 'message': e.toString(), 'recoverable': true});
      }
    } else if (type == 'dispose') {
      await worker.dispose();
      mainPort.send({'type': 'disposed'});
      receivePort.close();
      Isolate.exit();
    }
  }
}

class _NativeYoloWorker {
  _NativeYoloWorker(this._config);

  final Map<String, dynamic> _config;
  late final _NativeBindings _bindings;
  Pointer<Void>? _handle;

  Future<void> initialize() async {
    final lib = _openLibrary();
    _bindings = _NativeBindings(lib);
    final Pointer<Utf8> modelPathPtr = (_config['modelPath'] as String).toNativeUtf8();
    _handle = _bindings.create(
      modelPathPtr,
      _config['inputWidth'] as int,
      _config['inputHeight'] as int,
      _config['threads'] as int,
      _config['maxDetections'] as int,
      (_config['confidenceThreshold'] as num).toDouble(),
      (_config['iouThreshold'] as num).toDouble(),
      (_config['useGpu'] as bool? ?? false) ? 1 : 0,
      (_config['allowFp16'] as bool? ?? true) ? 1 : 0,
    );
    calloc.free(modelPathPtr);
    if (_handle == null || _handle == nullptr) {
      throw Exception('Failed to create YOLO engine');
    }
  }

  List<Map<String, dynamic>> processFrame(Map<String, dynamic> message) {
    if (_handle == null) {
      throw StateError('Native engine not initialized');
    }
    final frame = _NativeFrame.fromMessage(message);
    final Pointer<Uint8> yPtr = calloc<Uint8>(frame.yBytes.length);
    final Pointer<Uint8> uPtr = calloc<Uint8>(frame.uBytes.length);
    final Pointer<Uint8> vPtr = calloc<Uint8>(frame.vBytes.length);
    yPtr.asTypedList(frame.yBytes.length).setAll(0, frame.yBytes);
    uPtr.asTypedList(frame.uBytes.length).setAll(0, frame.uBytes);
    vPtr.asTypedList(frame.vBytes.length).setAll(0, frame.vBytes);

    final Pointer<_YoloDetections> detectionsPtr = calloc<_YoloDetections>();
    final int status = _bindings.process(
      _handle!,
      yPtr,
      uPtr,
      vPtr,
      frame.yRowStride,
      frame.uvRowStride,
      frame.uvPixelStride,
      frame.width,
      frame.height,
      frame.rotation,
      detectionsPtr,
    );
    calloc.free(yPtr);
    calloc.free(uPtr);
    calloc.free(vPtr);
    if (status != 0) {
      _bindings.releaseDetections(detectionsPtr);
      calloc.free(detectionsPtr);
      throw Exception('Native processFrame failed: status=$status');
    }

    final detections = <Map<String, dynamic>>[];
    final Pointer<_YoloDetection> items = detectionsPtr.ref.detections;
    final int count = detectionsPtr.ref.count;
    for (int i = 0; i < count; i++) {
      final detection = items[i];
      detections.add({
        'left': detection.left,
        'top': detection.top,
        'right': detection.right,
        'bottom': detection.bottom,
        'score': detection.score,
        'classIndex': detection.classIndex,
      });
    }
    _bindings.releaseDetections(detectionsPtr);
    calloc.free(detectionsPtr);
    return detections;
  }

  Future<void> dispose() async {
    final pointer = _handle;
    if (pointer != null && pointer != nullptr) {
      _bindings.destroy(pointer);
      _handle = null;
    }
  }
}

class _NativeFrame {
  _NativeFrame({
    required this.width,
    required this.height,
    required this.rotation,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
  });

  final int width;
  final int height;
  final int rotation;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;

  factory _NativeFrame.fromMessage(Map<String, dynamic> map) {
    final TransferableTypedData yData = map['yData'] as TransferableTypedData;
    final TransferableTypedData uData = map['uData'] as TransferableTypedData;
    final TransferableTypedData vData = map['vData'] as TransferableTypedData;
    return _NativeFrame(
      width: map['width'] as int,
      height: map['height'] as int,
      rotation: map['rotation'] as int,
      yRowStride: map['yRowStride'] as int,
      uvRowStride: map['uvRowStride'] as int,
      uvPixelStride: map['uvPixelStride'] as int,
      yBytes: yData.materialize().asUint8List(),
      uBytes: uData.materialize().asUint8List(),
      vBytes: vData.materialize().asUint8List(),
    );
  }
}

DynamicLibrary _openLibrary() {
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libyolo_engine.so');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('yolo_engine.dll');
  }
  throw UnsupportedError('Unsupported platform ${Platform.operatingSystem}');
}

class _NativeBindings {
  _NativeBindings(DynamicLibrary library)
      : create = library.lookupFunction<_CreateEngineNative, _CreateEngineDart>('YoloEngineCreate'),
        destroy = library.lookupFunction<_DestroyEngineNative, _DestroyEngineDart>('YoloEngineDestroy'),
        process = library.lookupFunction<_ProcessFrameNative, _ProcessFrameDart>('YoloEngineProcessYuvFrame'),
        releaseDetections = library.lookupFunction<_ReleaseDetectionsNative, _ReleaseDetectionsDart>('YoloEngineReleaseDetections');

  final _CreateEngineDart create;
  final _DestroyEngineDart destroy;
  final _ProcessFrameDart process;
  final _ReleaseDetectionsDart releaseDetections;
}

base class _YoloDetection extends Struct {
  @Float()
  external double left;

  @Float()
  external double top;

  @Float()
  external double right;

  @Float()
  external double bottom;

  @Float()
  external double score;

  @Int32()
  external int classIndex;
}

base class _YoloDetections extends Struct {
  external Pointer<_YoloDetection> detections;

  @Int32()
  external int count;
}

typedef _CreateEngineNative = Pointer<Void> Function(
  Pointer<Utf8> modelPath,
  Int32 inputWidth,
  Int32 inputHeight,
  Int32 threads,
  Int32 maxDetections,
  Float confidenceThreshold,
  Float iouThreshold,
  Int32 useGpu,
  Int32 allowFp16,
);
typedef _CreateEngineDart = Pointer<Void> Function(
  Pointer<Utf8> modelPath,
  int inputWidth,
  int inputHeight,
  int threads,
  int maxDetections,
  double confidenceThreshold,
  double iouThreshold,
  int useGpu,
  int allowFp16,
);

typedef _DestroyEngineNative = Void Function(Pointer<Void> handle);
typedef _DestroyEngineDart = void Function(Pointer<Void> handle);

typedef _ProcessFrameNative = Int32 Function(
  Pointer<Void> handle,
  Pointer<Uint8> yPlane,
  Pointer<Uint8> uPlane,
  Pointer<Uint8> vPlane,
  Int32 yRowStride,
  Int32 uvRowStride,
  Int32 uvPixelStride,
  Int32 width,
  Int32 height,
  Int32 rotation,
  Pointer<_YoloDetections> result,
);
typedef _ProcessFrameDart = int Function(
  Pointer<Void> handle,
  Pointer<Uint8> yPlane,
  Pointer<Uint8> uPlane,
  Pointer<Uint8> vPlane,
  int yRowStride,
  int uvRowStride,
  int uvPixelStride,
  int width,
  int height,
  int rotation,
  Pointer<_YoloDetections> result,
);

typedef _ReleaseDetectionsNative = Void Function(Pointer<_YoloDetections> detections);
typedef _ReleaseDetectionsDart = void Function(Pointer<_YoloDetections> detections);
