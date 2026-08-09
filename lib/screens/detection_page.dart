import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yaml/yaml.dart';

import '../detection/detection.dart';
import '../detection/iou.dart';
import '../detection/stability_engine.dart';
import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../native/image_yuv_frame_decoder.dart';
import '../native/native_yolo_engine.dart';
import '../repositories/species_repository.dart';
import '../services/country_location_service.dart';
import '../services/location_capture_service.dart';
import '../services/location_label_service.dart';
import '../services/online_identification_service.dart';
import '../services/settings_service.dart';

const Color _deepGreen = Color(0xFF1F4E3D);
const Color _accentGreen = Color(0xFF8FBFA1);
const Color _highlightGreen = Color(0xFF7CD39A);
const Color _mutedWhite = Color(0xCCFFFFFF);

String _normalizeStaticName(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('_', ' ');
  return normalized.replaceAll(RegExp(r'\s+'), ' ');
}

enum _DetectionUiState {
  scanning,
  possibleMatch,
  confirming,
  matchFound,
  lowConfidence,
}

enum _IdentificationMode { offline, online }

class _DetectionUiPresentation {
  final _DetectionUiState state;
  final StableTrack? displayTrack;
  final String statusText;
  final IconData statusIcon;
  final String? bannerTitle;
  final String? bannerSubtitle;
  final String? bannerDetail;
  final String? speciesId;
  final bool canOpenSpecies;

  const _DetectionUiPresentation({
    required this.state,
    required this.displayTrack,
    required this.statusText,
    required this.statusIcon,
    required this.bannerTitle,
    required this.bannerSubtitle,
    required this.bannerDetail,
    required this.speciesId,
    required this.canOpenSpecies,
  });
}

class _ModelMetadata {
  final List<String> labels;
  final int inputWidth;
  final int inputHeight;

  const _ModelMetadata({
    required this.labels,
    required this.inputWidth,
    required this.inputHeight,
  });
}

class _YoloModelDescriptor {
  final String modelId;
  final String displayName;
  final String modelAssetPath;
  final String metadataAssetPath;
  final String materializedFileName;
  final double nativeConfidenceThreshold;
  final double displayConfidenceThreshold;
  final double iouThreshold;
  final bool useGpu;
  final bool allowFp16;

  const _YoloModelDescriptor({
    required this.modelId,
    required this.displayName,
    required this.modelAssetPath,
    required this.metadataAssetPath,
    required this.materializedFileName,
    required this.nativeConfidenceThreshold,
    required this.displayConfidenceThreshold,
    required this.iouThreshold,
    required this.useGpu,
    required this.allowFp16,
  });
}

class _CaptureSelection {
  final List<Detection> candidates;
  final bool isAmbiguous;

  const _CaptureSelection({
    required this.candidates,
    required this.isAmbiguous,
  });

  Detection get primary => candidates.first;

  Detection? get secondary => candidates.length > 1 ? candidates[1] : null;
}

class _LiveDetectionSnapshot {
  final List<Detection> detections;
  final int timestampMs;

  const _LiveDetectionSnapshot({
    required this.detections,
    required this.timestampMs,
  });
}

class _OnlineIdentificationContext {
  final String? country;
  final String? region;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final DateTime? capturedAt;
  final String? locationLabel;

  const _OnlineIdentificationContext({
    this.country,
    this.region,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.capturedAt,
    this.locationLabel,
  });

  OnlineIdentificationLocation toRequestLocation() {
    return OnlineIdentificationLocation(
      country: country,
      region: region,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

class _ScanWindowSupport {
  final String label;
  final int? classIndex;
  final String? modelId;
  final String? modelDisplayName;
  final Set<String> modelIds = <String>{};
  int framesSeen = 0;
  double scoreSum = 0.0;
  double maxScore = 0.0;

  _ScanWindowSupport({
    required this.label,
    required this.classIndex,
    required this.modelId,
    required this.modelDisplayName,
  });

  void add(Detection detection) {
    framesSeen += 1;
    scoreSum += detection.finalScore;
    if (detection.finalScore > maxScore) {
      maxScore = detection.finalScore;
    }
    if (detection.sourceModelIds.isNotEmpty) {
      modelIds.addAll(detection.sourceModelIds);
    } else {
      modelIds.add(detection.modelId);
    }
  }

  double get averageScore => framesSeen == 0 ? 0.0 : scoreSum / framesSeen;

  double get supportScore {
    final double frameScore = (framesSeen / 10).clamp(0.0, 1.0);
    final double modelScore = modelIds.length > 1 ? 1.0 : 0.55;
    return (frameScore * 0.30) +
        (averageScore * 0.30) +
        (maxScore * 0.25) +
        (modelScore * 0.15);
  }
}

class _ScanWindowSummary {
  final int startedAtMs;
  final int endedAtMs;
  final Map<String, _ScanWindowSupport> supportByName;

  const _ScanWindowSummary({
    required this.startedAtMs,
    required this.endedAtMs,
    required this.supportByName,
  });

  int get windowDurationMs => (endedAtMs - startedAtMs).clamp(0, 60000);

  int get windowFrameCount =>
      supportByName.values.fold<int>(0, (sum, support) => sum + support.framesSeen);

  double supportFor(Detection detection) {
    return supportByName[_normalizeStaticName(detection.speciesName)]
            ?.supportScore ??
        0.0;
  }

  List<_ScanWindowSupport> get rankedSupports {
    final ranked = supportByName.values.toList()
      ..sort((a, b) => b.supportScore.compareTo(a.supportScore));
    return ranked;
  }
}

class _ScanRankedCandidate {
  final Detection detection;
  final double liveSupport;
  final double finalScore;

  const _ScanRankedCandidate({
    required this.detection,
    required this.liveSupport,
    required this.finalScore,
  });
}

class _ResultWindowMetrics {
  final double top1VoteRatio;
  final int windowFrameCount;
  final int windowDurationMs;
  final int stabilityWinCount;
  final int stabilityWindowSize;

  const _ResultWindowMetrics({
    required this.top1VoteRatio,
    required this.windowFrameCount,
    required this.windowDurationMs,
    required this.stabilityWinCount,
    required this.stabilityWindowSize,
  });
}

class DetectionPage extends StatefulWidget {
  const DetectionPage({super.key});

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage>
    with WidgetsBindingObserver {
  CameraController? _camera;
  final Map<String, NativeYoloEngine> _liveEngines =
      <String, NativeYoloEngine>{};
  final Map<String, StreamSubscription<NativeYoloFrameResult>>
      _liveFrameResultSubs =
      <String, StreamSubscription<NativeYoloFrameResult>>{};
  final Map<String, StreamSubscription<String>> _liveErrorSubs =
      <String, StreamSubscription<String>>{};
  late DetectionStabilityEngine _stabilityEngine;
  List<String> _labels = [];
  final Map<String, _ModelMetadata> _modelMetadata =
      <String, _ModelMetadata>{};
  final Map<String, NativeYoloEngine> _captureEngines =
      <String, NativeYoloEngine>{};
  final Map<String, _LiveDetectionSnapshot> _liveDetectionSnapshots =
      <String, _LiveDetectionSnapshot>{};
  NativeYuvFrame? _latestFrame;
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;
  final SettingsService _settingsService = SettingsService.instance;
  final LocationCaptureService _locationCaptureService =
      LocationCaptureService.instance;
  final LocationLabelService _locationLabelService =
      LocationLabelService.instance;
  final CountryLocationService _countryLocationService =
      CountryLocationService.instance;
  final OnlineIdentificationService _onlineIdentificationService =
      OnlineIdentificationService.instance;
  final image_picker.ImagePicker _imagePicker = image_picker.ImagePicker();
  Map<String, String> _speciesIdByName = {};
  Map<String, String> _speciesIdByModelClass = {};
  Set<int> _lichenClassIndices = <int>{};
  Set<String> _lichenClassKeys = <String>{};
  Set<String> _lichenNames = <String>{};
  bool _isInitialized = false;
  bool _hasPermission = false;
  bool _engineReady = false;
  bool _isCapturing = false;
  bool _isScanning = false;
  bool _offlinePhotoLoading = false;
  bool _onlineLoading = false;
  _IdentificationMode _identificationMode = _IdentificationMode.offline;
  int _scanRemainingSeconds = 5;
  int _scanStartedAtMs = 0;
  Timer? _scanCountdownTimer;
  final List<Detection> _scanWindowDetections = <Detection>[];

  int _inputWidth = 640;
  int _inputHeight = 640;
  late Size _previewSize;
  bool _isFrontCamera = false;

  List<Detection> _detections = [];
  StableTrack? _primaryTrack;
  StableTrack? _lastStableTrack;
  int _lastStableTrackMs = 0;
  String? _errorMessage;
  int _streamFrameCount = 0;
  int _nativeResultCount = 0;
  int _lastStreamFrameMs = 0;
  int _lastDebugFrameSubmissionLogMs = 0;
  int _lastDebugTimingLogMs = 0;
  int _lastDebugLiveSummaryLogMs = 0;
  int _lastFpsFrameCount = 0;
  String? _lastDebugUiState;
  int _liveAlternatingCursor = 0;
  int _liveSkippedFrameCount = 0;
  final Map<String, int> _liveSubmittedFrameCountByModel = <String, int>{};
  final Map<String, int> _liveResultCountByModel = <String, int>{};
  final Map<String, int> _liveNativeRawCountByModel = <String, int>{};
  final Map<String, int> _liveNativeFilteredCountByModel = <String, int>{};
  final Map<String, int> _liveDetectionCountByModel = <String, int>{};
  final Map<String, int> _liveLatestSubmittedFrameByModel = <String, int>{};
  final Map<String, int> _liveLatestNativeFrameByModel = <String, int>{};
  static const int _uiHoldGraceMs = 1300;

  static const bool _dualLiveDetectionEnabled =
      bool.fromEnvironment('DUAL_LIVE_DETECTION');
  static const bool _dualLiveDebug = bool.fromEnvironment('DUAL_LIVE_DEBUG');
  static const String _dualLiveMode =
      String.fromEnvironment('DUAL_LIVE_MODE', defaultValue: 'primary');
  static const String _livePrimaryModelValue =
      String.fromEnvironment('LIVE_PRIMARY_MODEL', defaultValue: 'model_2');
  static const int _liveFusionWindowMs = 700;

  static const double _confThreshold = 0.30;
  static const double _nmsIoUThreshold = 0.45;
  static const double _crossModelMergeIoUThreshold = 0.5;
  static const double _crossModelAmbiguousMargin = 0.20;
  static const double _crossModelOverrideMargin = 0.25;
  static const double _crossModelCompetingMinScore = 0.45;
  static const double _dualLiveModel1RawConfidenceThreshold = 0.25;
  static const double _dualLiveModel2RawConfidenceThreshold = 0.40;
  static const double _dualLiveModel1VisibleConfidenceThreshold = 0.45;
  static const double _dualLiveModel2VisibleConfidenceThreshold = 0.50;
  static const double _dualLiveModel1StableConfidenceThreshold = 0.60;
  static const double _dualLiveModel2StableConfidenceThreshold = 0.65;
  static const double _boxTinyAreaRatio = 0.002;
  static const double _boxHugeAreaRatio = 0.85;
  static const double _boxExtremeAspectRatio = 8.0;
  static const double _boxSanityOverrideConfidence = 0.85;
  static const int _scanDurationSeconds = 5;
  static const double _scanCaptureWeight = 0.70;
  static const double _scanLiveWindowWeight = 0.30;
  static const double _scanFinalAcceptanceThreshold = 0.55;
  static const double _scanSecondaryMargin = 0.18;
  static const double _scanLivePossibleSupportThreshold = 0.45;

  static const _YoloModelDescriptor _model1 = _YoloModelDescriptor(
    modelId: 'model_1',
    displayName: 'Model 1',
    modelAssetPath: 'assets/models/1_yolo11n_float32.tflite',
    metadataAssetPath: 'assets/models/metadata_1.yaml',
    materializedFileName: '1_yolo11n_float32.tflite',
    nativeConfidenceThreshold: _confThreshold,
    displayConfidenceThreshold: 0.45,
    iouThreshold: _nmsIoUThreshold,
    useGpu: true,
    allowFp16: true,
  );

  static const _YoloModelDescriptor _model2 = _YoloModelDescriptor(
    modelId: 'model_2',
    displayName: 'Model 2',
    modelAssetPath: 'assets/models/yolo11n_float32.tflite',
    metadataAssetPath: 'assets/models/metadata.yaml',
    materializedFileName: 'yolo11n_float32.tflite',
    nativeConfidenceThreshold: _confThreshold,
    displayConfidenceThreshold: 0.45,
    iouThreshold: _nmsIoUThreshold,
    useGpu: true,
    allowFp16: true,
  );

  static const List<_YoloModelDescriptor> _captureModels =
      <_YoloModelDescriptor>[_model2, _model1];

  bool get _dualLiveAlternatingEnabled =>
      _dualLiveDetectionEnabled &&
      _dualLiveMode.trim().toLowerCase() == 'alternating';

  String get _activeLiveMode =>
      _dualLiveAlternatingEnabled ? 'alternating' : 'primary';

  _YoloModelDescriptor get _primaryLiveModel =>
      _modelForLiveValue(_livePrimaryModelValue);

  _YoloModelDescriptor get _secondaryLiveModel =>
      _primaryLiveModel.modelId == _model1.modelId ? _model2 : _model1;

  List<_YoloModelDescriptor> get _liveModels {
    if (_dualLiveAlternatingEnabled) {
      return <_YoloModelDescriptor>[_primaryLiveModel, _secondaryLiveModel];
    }
    return <_YoloModelDescriptor>[_primaryLiveModel];
  }

  _YoloModelDescriptor _modelForLiveValue(String value) {
    final normalized = value.trim().toLowerCase().replaceAll('-', '_');
    if (normalized == 'model_1' ||
        normalized == 'model1' ||
        normalized == '1') {
      return _model1;
    }
    return _model2;
  }

  bool _liveUseGpuFor(_YoloModelDescriptor model) {
    if (!_dualLiveAlternatingEnabled) {
      return model.useGpu;
    }
    return model.modelId == _primaryLiveModel.modelId && model.useGpu;
  }

  int _liveThreadCountFor(_YoloModelDescriptor model) {
    if (!Platform.isAndroid) {
      return 2;
    }
    if (_dualLiveAlternatingEnabled &&
        model.modelId != _primaryLiveModel.modelId) {
      return 2;
    }
    return 3;
  }

  double _liveConfidenceThresholdFor(_YoloModelDescriptor model) {
    if (!_dualLiveAlternatingEnabled) {
      return model.displayConfidenceThreshold;
    }
    if (model.modelId == _model1.modelId) {
      return _dualLiveModel1VisibleConfidenceThreshold;
    }
    return _dualLiveModel2VisibleConfidenceThreshold;
  }

  double _liveNativeConfidenceThresholdFor(_YoloModelDescriptor model) {
    if (!_dualLiveAlternatingEnabled) {
      return model.nativeConfidenceThreshold;
    }
    if (model.modelId == _model1.modelId) {
      return _dualLiveModel1RawConfidenceThreshold;
    }
    return _dualLiveModel2RawConfidenceThreshold;
  }

  double _liveStableConfidenceThresholdFor(_YoloModelDescriptor model) {
    if (!_dualLiveAlternatingEnabled) {
      return _stabilityEngine.config.stableConfMin;
    }
    if (model.modelId == _model1.modelId) {
      return _dualLiveModel1StableConfidenceThreshold;
    }
    return _dualLiveModel2StableConfidenceThreshold;
  }

  StabilityConfig? _liveStabilityConfig() {
    if (!_dualLiveAlternatingEnabled) {
      return null;
    }
    return const StabilityConfig(
      modelDetectConfMin: <String, double>{
        'model_1': _dualLiveModel1VisibleConfidenceThreshold,
        'model_2': _dualLiveModel2VisibleConfidenceThreshold,
        'merged': _dualLiveModel1VisibleConfidenceThreshold,
      },
      modelStableConfMin: <String, double>{
        'model_1': _dualLiveModel1StableConfidenceThreshold,
        'model_2': _dualLiveModel2StableConfidenceThreshold,
        'merged': _dualLiveModel1StableConfidenceThreshold,
      },
      marginMin: _crossModelAmbiguousMargin,
      minObservationsForStability: 3,
      adaptiveHighConfWins: 3,
      adaptiveMediumConfWins: 3,
    );
  }

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
      final model2Metadata = await _loadModelMetadata(
        _model2.metadataAssetPath,
      );
      final model1Metadata = await _loadModelMetadata(
        _model1.metadataAssetPath,
      );
      _modelMetadata[_model2.modelId] = model2Metadata;
      _modelMetadata[_model1.modelId] = model1Metadata;
      _labels = model2Metadata.labels;
      _inputWidth = model2Metadata.inputWidth;
      _inputHeight = model2Metadata.inputHeight;
      debugPrint('labels.length: ${_labels.length}');
      _stabilityEngine = DetectionStabilityEngine(
        labels: _labels,
        config: _liveStabilityConfig(),
      );
      _engineReady = true;
      await _initializeLiveEngines();
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

  Future<_ModelMetadata> _loadModelMetadata(String assetPath) async {
    final yamlStr = await rootBundle.loadString(assetPath);
    final doc = loadYaml(yamlStr);

    List<String> names = [];
    int inputWidth = 640;
    int inputHeight = 640;
    if (doc is YamlMap) {
      final Size? rootSize = _inputShapeFromMetadata(doc);
      if (rootSize != null) {
        inputWidth = rootSize.width.toInt();
        inputHeight = rootSize.height.toInt();
      }
      dynamic namesNode;
      if (doc.containsKey('names')) {
        namesNode = doc['names'];
      } else if (doc.containsKey('model') && doc['model'] is YamlMap) {
        final modelNode = doc['model'] as YamlMap;
        final Size? modelSize = _inputShapeFromMetadata(modelNode);
        if (modelSize != null) {
          inputWidth = modelSize.width.toInt();
          inputHeight = modelSize.height.toInt();
        }
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
    return _ModelMetadata(
      labels: names,
      inputWidth: inputWidth,
      inputHeight: inputHeight,
    );
  }

  Size? _inputShapeFromMetadata(YamlMap source) {
    final imgsz = source['imgsz'];
    if (imgsz is YamlList && imgsz.isNotEmpty) {
      if (imgsz.length >= 2 && imgsz[0] is num && imgsz[1] is num) {
        return Size(
          (imgsz[0] as num).toDouble(),
          (imgsz[1] as num).toDouble(),
        );
      } else if (imgsz.length == 1 && imgsz[0] is num) {
        final size = (imgsz[0] as num).toInt();
        return Size(size.toDouble(), size.toDouble());
      }
    }
    return null;
  }

  Future<void> _initializeLiveEngines() async {
    await _disposeLiveEngines();

    final liveModels = _liveModels;
    if (kDebugMode) {
      debugPrint(
        '[DetectTiming][live] mode=$_activeLiveMode '
        'dual=$_dualLiveDetectionEnabled primary=${_primaryLiveModel.modelId} '
        'models=${liveModels.map((model) => model.modelId).join(',')}',
      );
    }

    for (final model in liveModels) {
      final metadata = _modelMetadata[model.modelId];
      if (metadata == null) {
        throw StateError('Metadata not loaded for ${model.modelId}');
      }
      final modelPath = await _materializeAsset(
        model.modelAssetPath,
        model.materializedFileName,
      );
      if (_dualLiveDebug) {
        debugPrint(
          '[DUAL_LIVE] init ${model.modelId} modelAsset=${model.modelAssetPath} '
          'metadata=${model.metadataAssetPath} size=${metadata.inputWidth}x${metadata.inputHeight} '
          'nativeThreshold=${_liveNativeConfidenceThresholdFor(model).toStringAsFixed(2)} '
          'displayThreshold=${_liveConfidenceThresholdFor(model).toStringAsFixed(2)} '
          'stabilityThreshold=${_liveStableConfidenceThresholdFor(model).toStringAsFixed(2)} '
          'materializedPath=$modelPath',
        );
      }
      final engine = await NativeYoloEngine.create(
        NativeYoloConfig(
          modelPath: modelPath,
          debugLabel: 'live-${model.modelId}',
          inputWidth: metadata.inputWidth,
          inputHeight: metadata.inputHeight,
          threads: _liveThreadCountFor(model),
          maxDetections: 150,
          confidenceThreshold: _liveNativeConfidenceThresholdFor(model),
          iouThreshold: model.iouThreshold,
          displayConfidenceThreshold: _liveConfidenceThresholdFor(model),
          useGpu: _liveUseGpuFor(model),
          allowFp16: model.allowFp16,
        ),
      );
      _liveEngines[model.modelId] = engine;
      _liveFrameResultSubs[model.modelId] = engine.frameResults.listen(
        (result) => _onNativeFrameResult(model, result),
      );
      _liveErrorSubs[model.modelId] = engine.errors.listen((msg) {
        debugPrint('Native engine warning (${model.modelId}): $msg');
      });
    }
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

  void _onNativeFrameResult(
    _YoloModelDescriptor model,
    NativeYoloFrameResult result,
  ) {
    if (!mounted) return;
    if (!_engineReady) return;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    _nativeResultCount += 1;
    _liveResultCountByModel[model.modelId] =
        (_liveResultCountByModel[model.modelId] ?? 0) + 1;
    _liveLatestNativeFrameByModel[model.modelId] = result.frameId;
    _liveNativeRawCountByModel[model.modelId] = result.rawDetectionCount;
    _liveNativeFilteredCountByModel[model.modelId] =
        result.filteredDetectionCount;
    _liveDetectionCountByModel[model.modelId] = result.detections.length;
    final List<Detection> mapped = _mapNativeDetections(
      model,
      result.detections,
      targetInputWidth: _inputWidth,
      targetInputHeight: _inputHeight,
      timestampMs: nowMs,
      frameIndex: result.frameId,
    );
    final List<Detection> acceptedMapped = _filterLiveDetections(
      mapped,
      frameIndex: result.frameId,
    );
    _recordScanWindowDetections(acceptedMapped);
    _liveDetectionSnapshots[model.modelId] = _LiveDetectionSnapshot(
      detections: acceptedMapped,
      timestampMs: nowMs,
    );
    final List<Detection> liveDetections = _currentLiveDetections(nowMs);
    final Map<String, int> cacheCounts = _countDetectionsByModel(
      liveDetections,
    );
    final Map<String, int> thresholdCounts = _countDetectionsByModel(
      liveDetections
          .where((detection) =>
              detection.confidence >=
              _stabilityEngine.config.detectConfMinFor(detection))
          .toList(growable: false),
    );
    final List<StableTrack> stableTracks = _stabilityEngine.processFrame(
      liveDetections,
      nowMs,
    );
    final StableTrack? primaryTrack = _selectPrimaryTrack(stableTracks);
    if (primaryTrack != null &&
        (primaryTrack.lockedClassKey != null || primaryTrack.isStable)) {
      _lastStableTrack = primaryTrack;
      _lastStableTrackMs = nowMs;
    }
    _logDetectionTiming(
      nowMs: nowMs,
      resultModel: model,
      frameDetectionCount: liveDetections.length,
      primaryTrack: primaryTrack,
    );
    _logDualLiveResult(
      model: model,
      result: result,
      mappedCount: acceptedMapped.length,
      cacheCounts: cacheCounts,
      thresholdCounts: thresholdCounts,
      stableTracks: stableTracks,
      primaryTrack: primaryTrack,
    );
    _logDualLiveStability(stableTracks, primaryTrack);
    setState(() {
      _detections = liveDetections;
      _primaryTrack = primaryTrack;
    });
  }

  List<Detection> _currentLiveDetections(int nowMs) {
    final staleModelIds = <String>[];
    final combined = <Detection>[];
    for (final entry in _liveDetectionSnapshots.entries) {
      if (nowMs - entry.value.timestampMs > _liveFusionWindowMs) {
        staleModelIds.add(entry.key);
        continue;
      }
      combined.addAll(entry.value.detections);
    }
    for (final modelId in staleModelIds) {
      _liveDetectionSnapshots.remove(modelId);
    }
    if (combined.length < 2) {
      return combined;
    }
    return _mergeCrossModelDetections(combined);
  }

  Map<String, int> _countDetectionsByModel(List<Detection> detections) {
    final counts = <String, int>{};
    for (final detection in detections) {
      final sourceIds = detection.sourceModelIds.isEmpty
          ? <String>[detection.modelId]
          : detection.sourceModelIds;
      for (final modelId in sourceIds) {
        counts[modelId] = (counts[modelId] ?? 0) + 1;
      }
    }
    return counts;
  }

  Map<String, int> _countStableTracksByModel(List<StableTrack> tracks) {
    final counts = <String, int>{};
    for (final track in tracks) {
      final modelId = track.lockedModelId ?? track.top1ModelId;
      if (modelId == null) {
        continue;
      }
      if (modelId == 'merged') {
        counts[modelId] = (counts[modelId] ?? 0) + 1;
        continue;
      }
      counts[modelId] = (counts[modelId] ?? 0) + 1;
    }
    return counts;
  }

  List<Detection> _filterLiveDetections(
    List<Detection> detections, {
    required int frameIndex,
  }) {
    final accepted = <Detection>[];
    for (final detection in detections) {
      final reason = _liveRejectionReason(detection);
      if (reason == null) {
        accepted.add(detection);
        _logDualLiveDetectionDecision(
          frameIndex: frameIndex,
          detection: detection,
          accepted: true,
          reason: 'accepted',
        );
      } else {
        _logDualLiveDetectionDecision(
          frameIndex: frameIndex,
          detection: detection,
          accepted: false,
          reason: reason,
        );
      }
    }
    return accepted;
  }

  void _recordScanWindowDetections(List<Detection> detections) {
    if (!_isScanning || _isCapturing || detections.isEmpty) {
      return;
    }
    for (final detection in detections) {
      if (detection.finalScore <
          _stabilityEngine.config.detectConfMinFor(detection)) {
        continue;
      }
      _scanWindowDetections.add(detection);
    }
  }

  _ScanWindowSummary _buildScanWindowSummary(int endedAtMs) {
    final supportByName = <String, _ScanWindowSupport>{};
    for (final detection in _scanWindowDetections) {
      final String key = _normalizeName(detection.speciesName);
      if (key.isEmpty || key == 'unknown') {
        continue;
      }
      final support = supportByName.putIfAbsent(
        key,
        () => _ScanWindowSupport(
          label: detection.speciesName,
          classIndex: detection.sourceClassId,
          modelId: detection.modelId,
          modelDisplayName: detection.sourceDisplayName,
        ),
      );
      support.add(detection);
    }
    return _ScanWindowSummary(
      startedAtMs: _scanStartedAtMs == 0 ? endedAtMs : _scanStartedAtMs,
      endedAtMs: endedAtMs,
      supportByName: supportByName,
    );
  }

  String? _liveRejectionReason(Detection detection) {
    final box = detection.box;
    final bool invalidCoordinates = box.left.isNaN ||
        box.top.isNaN ||
        box.right.isNaN ||
        box.bottom.isNaN ||
        box.left < 0 ||
        box.top < 0 ||
        box.right <= box.left ||
        box.bottom <= box.top ||
        box.right > _inputWidth ||
        box.bottom > _inputHeight;
    if (invalidCoordinates) {
      return 'invalid_coordinates';
    }

    final double confidence = detection.finalScore;
    if (confidence >= _boxSanityOverrideConfidence) {
      return null;
    }
    final double areaRatio = _boxAreaRatio(detection.box);
    if (areaRatio < _boxTinyAreaRatio) {
      return 'tiny_box';
    }
    if (areaRatio > _boxHugeAreaRatio) {
      return 'huge_box';
    }
    final double aspectRatio = _boxAspectRatio(detection.box);
    if (aspectRatio > _boxExtremeAspectRatio) {
      return 'extreme_aspect_ratio';
    }
    return null;
  }

  void _logDualLiveDetectionDecision({
    required int frameIndex,
    required Detection detection,
    required bool accepted,
    required String reason,
  }) {
    if (!_dualLiveDebug) {
      return;
    }
    debugPrint(
      '[DUAL_LIVE] ${accepted ? 'accept' : 'reject'} frame=$frameIndex '
      'model=${detection.modelId} species=${detection.speciesName} '
      'sourceClassId=${detection.sourceClassId} '
      'rawConfidence=${detection.rawConfidence.toStringAsFixed(3)} '
      'finalScore=${detection.finalScore.toStringAsFixed(3)} '
      'box=${detection.box.width.toStringAsFixed(1)}x'
      '${detection.box.height.toStringAsFixed(1)} '
      'areaRatio=${_boxAreaRatio(detection.box).toStringAsFixed(4)} '
      'reason=$reason',
    );
  }

  double _boxAreaRatio(Rect box) {
    final double frameArea = _inputWidth * _inputHeight.toDouble();
    if (frameArea <= 0) {
      return 0.0;
    }
    return (box.width * box.height) / frameArea;
  }

  double _boxAspectRatio(Rect box) {
    final double width = box.width.abs();
    final double height = box.height.abs();
    if (width <= 0 || height <= 0) {
      return double.infinity;
    }
    return width > height ? width / height : height / width;
  }

  void _logDualLiveResult({
    required _YoloModelDescriptor model,
    required NativeYoloFrameResult result,
    required int mappedCount,
    required Map<String, int> cacheCounts,
    required Map<String, int> thresholdCounts,
    required List<StableTrack> stableTracks,
    required StableTrack? primaryTrack,
  }) {
    if (!_dualLiveDebug) {
      return;
    }
    final int submittedFrame =
        _liveLatestSubmittedFrameByModel[model.modelId] ?? _streamFrameCount;
    final String overlayWinner =
        primaryTrack?.lockedModelId ?? primaryTrack?.top1ModelId ?? 'none';
    final Map<String, int> stabilityCounts =
        _countStableTracksByModel(stableTracks);
    debugPrint(
      '[DUAL_LIVE] frame=$submittedFrame nativeFrame=${result.frameId} '
      '${model.modelId} nativeDetections=${result.rawDetectionCount} '
      'topClass=${result.topRawClassId ?? 'none'} '
      'topConf=${_formatDebugConfidence(result.topRawConfidence)}',
    );
    debugPrint(
      '[DUAL_LIVE] threshold model=${model.modelId} '
      'threshold=${result.displayConfidenceThreshold.toStringAsFixed(2)} '
      'before=${result.rawDetectionCount} '
      'after=${result.filteredDetectionCount} '
      'topRejected=${_formatDebugConfidence(result.topRejectedConfidence)}',
    );
    debugPrint(
      '[DUAL_LIVE] mapped model=${model.modelId} mappedCount=$mappedCount '
      '${_debugMappedDetectionSummary(model, mappedCount)}',
    );
    debugPrint(
      '[DUAL_LIVE] stability-summary model=${model.modelId} '
      'afterThreshold=${thresholdCounts[model.modelId] ?? 0} '
      'cache=${cacheCounts[model.modelId] ?? 0} '
      'stabilityCandidates=${thresholdCounts[model.modelId] ?? 0} '
      'stableTracks=${stabilityCounts[model.modelId] ?? 0} '
      'overlayWinner=$overlayWinner workerMs=${result.workerMs ?? -1}',
    );
  }

  String _debugMappedDetectionSummary(
    _YoloModelDescriptor model,
    int mappedCount,
  ) {
    if (mappedCount <= 0) {
      final labels = _modelMetadata[model.modelId]?.labels;
      final labelCount = labels?.length ?? 0;
      return 'mappingFailures=0 labelCount=$labelCount';
    }
    final snapshot = _liveDetectionSnapshots[model.modelId];
    if (snapshot == null || snapshot.detections.isEmpty) {
      return 'mappingFailures=0';
    }
    final detection = snapshot.detections.first;
    final bool mappingFailed = detection.speciesName == 'Unknown';
    return 'sourceClassId=${detection.sourceClassId} '
        'namespaced=${detection.namespacedClassId} '
        'species=${detection.speciesName} '
        'mappingFailures=${mappingFailed ? 1 : 0}';
  }

  String _formatDebugConfidence(double? value) {
    if (value == null) {
      return 'none';
    }
    return value.toStringAsFixed(3);
  }

  void _logDualLiveStability(
    List<StableTrack> stableTracks,
    StableTrack? primaryTrack,
  ) {
    if (!_dualLiveDebug) {
      return;
    }
    for (final track in stableTracks) {
      final key = track.lockedClassKey ?? track.top1ClassKey ?? 'none';
      final modelId = track.lockedModelId ?? track.top1ModelId ?? 'none';
      final accepted = track.isProvisional || track.isStable;
      final reason = _stabilityDecisionReason(track);
      debugPrint(
        '[DUAL_LIVE] stability key=$key model=$modelId '
        'accepted=$accepted ageMs=${track.windowDurationMs} '
        'frames=${track.windowFrameCount} wins=${track.stabilityWinCount}/'
        '${track.requiredWinsForStability} stable=${track.isStable} '
        'reason=$reason',
      );
    }
    final winnerKey = primaryTrack?.lockedClassKey ??
        primaryTrack?.top1ClassKey ??
        'none';
    final winnerModel = primaryTrack?.lockedModelId ??
        primaryTrack?.top1ModelId ??
        'none';
    debugPrint(
      '[DUAL_LIVE] overlay winner=$winnerModel key=$winnerKey '
      'reason=${primaryTrack == null ? 'no_candidate' : 'stable_candidate'}',
    );
  }

  String _stabilityDecisionReason(StableTrack track) {
    if (track.isStable) {
      return 'accepted';
    }
    if (track.windowFrameCount <= 1) {
      return 'unstable_single_frame';
    }
    if (track.top1AvgConf < _stabilityEngine.config.stableConfMinFor(
      track.top1ModelId,
    )) {
      return 'below_stable_threshold';
    }
    return 'insufficient_observations';
  }

  List<Detection> _mapNativeDetections(
    _YoloModelDescriptor model,
    List<NativeDetection> detections, {
    required int targetInputWidth,
    required int targetInputHeight,
    int? timestampMs,
    int? frameIndex,
  }) {
    final metadata = _modelMetadata[model.modelId];
    if (metadata == null) {
      return const <Detection>[];
    }
    final double scaleX = targetInputWidth / metadata.inputWidth;
    final double scaleY = targetInputHeight / metadata.inputHeight;
    return detections
        .map((d) {
          final label = _labelForIndex(d.classIndex, model: model);
          final calibratedConfidence = _calibratedConfidence(model, d.score);
          final finalScore = _finalScore(
            model: model,
            rawConfidence: d.score,
            calibratedConfidence: calibratedConfidence,
          );
          return Detection(
            box: Rect.fromLTRB(
              d.left * scaleX,
              d.top * scaleY,
              d.right * scaleX,
              d.bottom * scaleY,
            ),
            confidence: finalScore,
            classId: d.classIndex,
            label: label,
            modelId: model.modelId,
            modelDisplayName: model.displayName,
            sourceClassId: d.classIndex,
            namespacedClassId: '${model.modelId}:${d.classIndex}',
            speciesName: label,
            rawConfidence: d.score,
            calibratedConfidence: calibratedConfidence,
            finalScore: finalScore,
            sourceModelIds: <String>[model.modelId],
            sourceModelDisplayNames: <String>[model.displayName],
            timestampMs: timestampMs,
            frameIndex: frameIndex,
          );
        })
        .toList(growable: false);
  }

  double _calibratedConfidence(_YoloModelDescriptor model, double raw) {
    return raw.clamp(0.0, 1.0);
  }

  double _finalScore({
    required _YoloModelDescriptor model,
    required double rawConfidence,
    required double calibratedConfidence,
  }) {
    return calibratedConfidence.clamp(0.0, 1.0);
  }

  String _labelForIndex(
    int index, {
    _YoloModelDescriptor model = _model2,
  }) {
    final labels = _modelMetadata[model.modelId]?.labels ?? _labels;
    if (index >= 0 && index < labels.length) {
      final label = labels[index].trim();
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
      final modelClassMap = <String, String>{};
      final lichenClassIndices = <int>{};
      final lichenClassKeys = <String>{};
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
          final String? modelId = item.modelId;
          final int? sourceClassId = item.sourceClassId;
          if (modelId != null && sourceClassId != null) {
            lichenClassKeys.add(_modelClassKey(modelId, sourceClassId));
          }
          if (scientific.isNotEmpty) {
            lichenNames.add(scientific);
          }
          if (common.isNotEmpty) {
            lichenNames.add(common);
          }
        }
        final String? modelId = item.modelId;
        final int? sourceClassId = item.sourceClassId;
        if (modelId != null && sourceClassId != null) {
          modelClassMap[_modelClassKey(modelId, sourceClassId)] = item.id;
        }
      }
      if (!mounted) return;
      setState(() {
        _speciesIdByName = map;
        _speciesIdByModelClass = modelClassMap;
        _lichenClassIndices = lichenClassIndices;
        _lichenClassKeys = lichenClassKeys;
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
    return _normalizeStaticName(value);
  }

  String? _speciesIdForLabel(String label) {
    if (_speciesIdByName.isEmpty) {
      return null;
    }
    return _speciesIdByName[_normalizeName(label)];
  }

  String _modelClassKey(String modelId, int sourceClassId) {
    return '$modelId:$sourceClassId';
  }

  String? _speciesIdForDetection({
    required String? modelId,
    required int? sourceClassId,
    required String label,
  }) {
    if (modelId != null && sourceClassId != null) {
      final String? speciesId =
          _speciesIdByModelClass[_modelClassKey(modelId, sourceClassId)];
      if (speciesId != null) {
        return speciesId;
      }
    }
    return _speciesIdForLabel(label);
  }

  bool _isLichenDetection({
    required int? classIndex,
    required String label,
    String? modelId,
  }) {
    if (modelId != null && classIndex != null) {
      return _lichenClassKeys.contains(_modelClassKey(modelId, classIndex));
    }
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
        .where((t) => t.lockedClassKey != null)
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

  void _logFrameSubmission(int nowMs, _YoloModelDescriptor model) {
    if (!kDebugMode) {
      return;
    }
    if (nowMs - _lastDebugFrameSubmissionLogMs < 1200) {
      return;
    }
    final int elapsedMs = _lastDebugLiveSummaryLogMs == 0
        ? 0
        : nowMs - _lastDebugLiveSummaryLogMs;
    final int elapsedFrames = _streamFrameCount - _lastFpsFrameCount;
    final double fps = elapsedMs <= 0 ? 0.0 : elapsedFrames * 1000 / elapsedMs;
    _lastDebugFrameSubmissionLogMs = nowMs;
    _lastDebugLiveSummaryLogMs = nowMs;
    _lastFpsFrameCount = _streamFrameCount;
    debugPrint(
      '[DetectTiming][live] frame-received ts=$nowMs mode=$_activeLiveMode '
      'submittedModel=${model.modelId} streamFrames=$_streamFrameCount '
      'nativeResults=$_nativeResultCount fps=${fps.toStringAsFixed(1)} '
      'submittedByModel=$_liveSubmittedFrameCountByModel '
      'resultsByModel=$_liveResultCountByModel '
      'skipped=$_liveSkippedFrameCount',
    );
  }

  void _logDetectionTiming({
    required int nowMs,
    required _YoloModelDescriptor resultModel,
    required int frameDetectionCount,
    required StableTrack? primaryTrack,
  }) {
    if (!kDebugMode) {
      return;
    }
    final int approxFrameToResultMs = _lastStreamFrameMs == 0
        ? 0
        : nowMs - _lastStreamFrameMs;
    final _DetectionUiPresentation presentation = _buildUiPresentation(
      primaryTrack,
      nowMs,
    );
    final String uiState = presentation.state.name;
    final bool shouldLog = (nowMs - _lastDebugTimingLogMs) >= 1200 ||
        _lastDebugUiState != uiState;
    if (!shouldLog) {
      return;
    }
    _lastDebugTimingLogMs = nowMs;
    _lastDebugUiState = uiState;
    final String label = primaryTrack?.lockedLabel ?? primaryTrack?.top1Label ?? '--';
    final String? winnerModel =
        primaryTrack?.lockedModelId ?? primaryTrack?.top1ModelId;
    final double confidence = primaryTrack?.top1AvgConf ?? 0.0;
    final int wins = primaryTrack?.stabilityWinCount ?? 0;
    final int requiredWins = primaryTrack?.requiredWinsForStability ?? 0;
    final int consecutiveWins = primaryTrack?.consecutiveTop1Wins ?? 0;
    debugPrint(
      '[DetectTiming][ui] inference-return ts=$nowMs frameToResultMs=$approxFrameToResultMs '
      'mode=$_activeLiveMode resultModel=${resultModel.modelId} '
      'dets=$frameDetectionCount detsByModel=$_liveDetectionCountByModel '
      'resultsByModel=$_liveResultCountByModel '
      'winnerModel=${winnerModel ?? 'none'} label="$label" '
      'conf=${confidence.toStringAsFixed(3)} '
      'wins=$wins/$requiredWins streak=$consecutiveWins stable=${primaryTrack?.isStable ?? false} '
      'ready=${primaryTrack?.isReadyToCapture ?? false} uiState=$uiState',
    );
  }

  _DetectionUiPresentation _buildUiPresentation(
    StableTrack? primaryTrack,
    int nowMs,
  ) {
    final StableTrack? heldStable =
        _lastStableTrack != null && (nowMs - _lastStableTrackMs) <= _uiHoldGraceMs
        ? _lastStableTrack
        : null;
    final StableTrack? displayTrack =
        primaryTrack ?? heldStable;

    if (primaryTrack == null && displayTrack == null) {
      return const _DetectionUiPresentation(
        state: _DetectionUiState.scanning,
        displayTrack: null,
        statusText: 'Scanning...',
        statusIcon: Icons.center_focus_strong,
        bannerTitle: null,
        bannerSubtitle: null,
        bannerDetail: null,
        speciesId: null,
        canOpenSpecies: false,
      );
    }

    final StableTrack? active = primaryTrack ?? displayTrack;
    final bool hasLocked = active?.lockedClassKey != null;
    final bool stable = active?.isStable ?? false;
    final bool ready = primaryTrack?.isReadyToCapture ?? false;
    final bool ambiguous = active?.isAmbiguous ?? false;
    final String? label = hasLocked ? active?.lockedLabel : active?.top1Label;
    final String? modelDisplayName = hasLocked
        ? active?.lockedModelDisplayName
        : active?.top1ModelDisplayName;
    final String? speciesId = label == null
        ? null
        : _speciesIdForDetection(
            modelId: hasLocked ? active?.lockedModelId : active?.top1ModelId,
            sourceClassId: hasLocked
                ? active?.lockedClassId
                : active?.top1ClassId,
            label: label,
          );
    final String? topConfidence = active == null
        ? null
        : '${(active.top1AvgConf * 100).toStringAsFixed(1)}%';
    final String? sourceText = modelDisplayName == null
        ? topConfidence
        : topConfidence == null
            ? modelDisplayName
            : '$topConfidence $modelDisplayName';

    if (ready && label != null) {
      return _DetectionUiPresentation(
        state: _DetectionUiState.matchFound,
        displayTrack: active,
        statusText: modelDisplayName == null
            ? 'Likely fungus: $label'
            : 'Likely fungus: $label ($modelDisplayName)',
        statusIcon: Icons.check_circle,
        bannerTitle: label,
        bannerSubtitle: topConfidence == null
            ? 'Capture recheck required'
            : 'Ready to capture • $topConfidence',
        bannerDetail: ambiguous && active?.top2Label != null
            ? 'Also possible: ${active!.top2Label}'
            : null,
        speciesId: speciesId,
        canOpenSpecies: speciesId != null,
      );
    }

    if ((hasLocked || stable) && label != null) {
      return _DetectionUiPresentation(
        state: _DetectionUiState.matchFound,
        displayTrack: active,
        statusText: modelDisplayName == null
            ? 'Likely: $label'
            : 'Likely: $label ($modelDisplayName)',
        statusIcon: Icons.shield_outlined,
        bannerTitle: label,
        bannerSubtitle: topConfidence == null
            ? 'Likely fungus'
            : 'Likely fungus $sourceText',
        bannerDetail: ambiguous && active?.top2Label != null
            ? 'Also possible: ${active!.top2Label}'
            : null,
        speciesId: speciesId,
        canOpenSpecies: speciesId != null,
      );
    }

    if (primaryTrack != null && primaryTrack.isProvisional && label != null) {
      final bool likely = primaryTrack.top1AvgConf >= 0.65;
      final String tier = likely ? 'Likely' : 'Possible';
      return _DetectionUiPresentation(
        state: likely
            ? _DetectionUiState.confirming
            : _DetectionUiState.possibleMatch,
        displayTrack: active,
        statusText: modelDisplayName == null
            ? '$tier: $label'
            : '$tier: $label ($modelDisplayName)',
        statusIcon: likely ? Icons.timelapse : Icons.search,
        bannerTitle: '$tier: $label',
        bannerSubtitle: topConfidence == null
            ? null
            : 'Confidence $sourceText',
        bannerDetail: ambiguous && active?.top2Label != null
            ? 'Also possible: ${active!.top2Label}'
            : null,
        speciesId: speciesId,
        canOpenSpecies: speciesId != null,
      );
    }

    if (heldStable != null && heldStable.lockedLabel != null) {
      final String? heldSpeciesId = _speciesIdForDetection(
        modelId: heldStable.lockedModelId ?? heldStable.top1ModelId,
        sourceClassId: heldStable.lockedClassId ?? heldStable.top1ClassId,
        label: heldStable.lockedLabel ?? heldStable.top1Label ?? '',
      );
      return _DetectionUiPresentation(
        state: _DetectionUiState.confirming,
        displayTrack: heldStable,
        statusText: 'Confirming...',
        statusIcon: Icons.timelapse,
        bannerTitle: heldStable.lockedLabel,
        bannerSubtitle: 'Rechecking current view...',
        bannerDetail: null,
        speciesId: heldSpeciesId,
        canOpenSpecies: heldSpeciesId != null,
      );
    }

    return const _DetectionUiPresentation(
      state: _DetectionUiState.lowConfidence,
      displayTrack: null,
      statusText: 'Low confidence — try another angle',
      statusIcon: Icons.warning_amber_rounded,
      bannerTitle: null,
      bannerSubtitle: null,
      bannerDetail: null,
      speciesId: null,
      canOpenSpecies: false,
    );
  }

  void _startTimedScan() {
    if (_isScanning || _isCapturing) {
      return;
    }
    _scanCountdownTimer?.cancel();
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _isScanning = true;
      _scanRemainingSeconds = _scanDurationSeconds;
      _scanStartedAtMs = nowMs;
      _scanWindowDetections.clear();
    });

    _scanCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final int next = _scanRemainingSeconds - 1;
      if (next <= 0) {
        timer.cancel();
        setState(() {
          _scanRemainingSeconds = 0;
        });
        unawaited(_finishTimedScan());
        return;
      }
      setState(() {
        _scanRemainingSeconds = next;
      });
    });
  }

  Future<void> _finishTimedScan() async {
    if (_isCapturing) {
      return;
    }
    _scanCountdownTimer?.cancel();
    final int endedAtMs = DateTime.now().millisecondsSinceEpoch;
    final _ScanWindowSummary scanSummary = _buildScanWindowSummary(endedAtMs);
    setState(() {
      _isScanning = false;
      _isCapturing = true;
    });

    String? photoPath;
    final navigator = Navigator.of(context);
    try {
      final captureFrame = _latestFrame;
      final Future<_CaptureSelection?> captureSelectionFuture =
          captureFrame == null
              ? Future<_CaptureSelection?>.value(null)
              : _runCaptureDetectors(captureFrame);
      photoPath = await _capturePhoto();
      if (!mounted) return;

      _CaptureSelection? captureSelection;
      try {
        captureSelection = await captureSelectionFuture;
      } catch (e, stack) {
        debugPrint('Capture detector warning: $e');
        debugPrintStack(stackTrace: stack);
      }

      final DetectionResultArgs args = _resultArgsFromTimedScan(
        captureSelection,
        scanSummary,
        photoPath,
      );
      await navigator.pushNamed('/detection-result', arguments: args);
    } finally {
      if (mounted) {
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
      }
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _scanRemainingSeconds = _scanDurationSeconds;
        });
      }
    }
  }

  Future<void> _startOnlineIdentificationFromCamera() async {
    if (_onlineLoading || _isCapturing || _isScanning) {
      return;
    }
    if (kDebugMode) {
      debugPrint('ONLINE_ID: online mode selected');
      debugPrint('ONLINE_ID: take photo action started');
    }

    String? photoPath;
    try {
      setState(() {
        _isCapturing = true;
      });
      photoPath = await _capturePhoto();
      if (photoPath == null || !mounted) {
        return;
      }
      await _runOnlineIdentification(photoPath);
    } finally {
      if (mounted) {
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
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _startOfflineIdentificationFromCamera() async {
    if (_offlinePhotoLoading || _onlineLoading || _isCapturing || _isScanning) {
      return;
    }

    try {
      setState(() {
        _isCapturing = true;
        _offlinePhotoLoading = true;
      });
      final photoPath = await _capturePhoto();
      if (photoPath == null || !mounted) {
        return;
      }
      await _runOfflinePhotoIdentification(photoPath);
    } finally {
      await _restartImageStreamAfterPhotoAction();
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _offlinePhotoLoading = false;
        });
      }
    }
  }

  Future<void> _selectOfflineIdentificationPhoto() async {
    if (_offlinePhotoLoading || _onlineLoading || _isCapturing || _isScanning) {
      return;
    }

    try {
      final image = await _imagePicker.pickImage(
        source: image_picker.ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (image == null || !mounted) {
        return;
      }
      setState(() {
        _isCapturing = true;
        _offlinePhotoLoading = true;
      });
      await _runOfflinePhotoIdentification(image.path);
    } catch (e, stack) {
      debugPrint('Offline photo selection error: $e');
      debugPrintStack(stackTrace: stack);
      _showMessage('Could not analyze the selected photo: $e');
    } finally {
      await _restartImageStreamAfterPhotoAction();
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _offlinePhotoLoading = false;
        });
      }
    }
  }

  Future<void> _runOfflinePhotoIdentification(String photoPath) async {
    if (!_engineReady) {
      _showMessage('Offline detection is still loading. Please try again.');
      return;
    }

    final navigator = Navigator.of(context);
    try {
      final frame = await ImageYuvFrameDecoder.decodeFile(photoPath);
      final selection = await _runCaptureDetectors(frame);
      if (!mounted) return;
      final args = _resultArgsFromStillPhoto(selection, photoPath);
      await navigator.pushNamed('/detection-result', arguments: args);
    } catch (e, stack) {
      debugPrint('Offline still-photo detection error: $e');
      debugPrintStack(stackTrace: stack);
      _showMessage('Could not analyze the selected photo: $e');
    }
  }

  DetectionResultArgs _resultArgsFromStillPhoto(
    _CaptureSelection? selection,
    String photoPath,
  ) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final emptySummary = _ScanWindowSummary(
      startedAtMs: nowMs,
      endedAtMs: nowMs,
      supportByName: <String, _ScanWindowSupport>{},
    );
    if (selection == null ||
        selection.primary.finalScore < _scanFinalAcceptanceThreshold) {
      return _uncertainResultArgsFromScan(
        emptySummary,
        photoPath,
        possibleCaptureSelection: selection,
      );
    }

    return _resultArgsFromCaptureSelection(
      selection,
      null,
      photoPath,
      metrics: const _ResultWindowMetrics(
        top1VoteRatio: 1.0,
        windowFrameCount: 1,
        windowDurationMs: 0,
        stabilityWinCount: 1,
        stabilityWindowSize: 1,
      ),
      isConfirmed: true,
    );
  }

  Future<void> _restartImageStreamAfterPhotoAction() async {
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
  }

  Future<void> _selectOnlineIdentificationPhoto() async {
    if (_onlineLoading || _isCapturing || _isScanning) {
      return;
    }
    if (kDebugMode) {
      debugPrint('ONLINE_ID: online mode selected');
      debugPrint('ONLINE_ID: select photo action started');
    }
    try {
      final image = await _imagePicker.pickImage(
        source: image_picker.ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (image == null || !mounted) {
        return;
      }
      await _runOnlineIdentification(image.path);
    } catch (e) {
      _showMessage('Could not select photo: $e');
    }
  }

  Future<void> _runOnlineIdentification(String photoPath) async {
    if (_onlineLoading) {
      return;
    }
    if (kDebugMode) {
      debugPrint('ONLINE_ID: backend request will start');
    }
    setState(() {
      _onlineLoading = true;
    });
    final navigator = Navigator.of(context);
    try {
      final contextData = await _buildOnlineIdentificationContext();
      final result = await _onlineIdentificationService.identifyPhoto(
        photoPath: photoPath,
        location: contextData.toRequestLocation(),
      );
      if (!mounted) return;
      await navigator.pushNamed(
        '/online-identification-result',
        arguments: OnlineIdentificationResultArgs(
          result: result,
          photoPath: photoPath,
          country: contextData.country,
          region: contextData.region,
          latitude: contextData.latitude,
          longitude: contextData.longitude,
          accuracyMeters: contextData.accuracyMeters,
          capturedAt: contextData.capturedAt,
          locationLabel: contextData.locationLabel,
        ),
      );
    } on OnlineIdentificationException catch (e) {
      if (kDebugMode) {
        debugPrint('ONLINE_ID: error code ${e.code}');
        debugPrint('ONLINE_ID: error message ${e.message}');
      }
      _showMessage(e.message);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ONLINE_ID: unexpected error ${e.runtimeType}: $e');
      }
      _showMessage('Online identification failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _onlineLoading = false;
        });
      }
    }
  }

  Future<_OnlineIdentificationContext> _buildOnlineIdentificationContext() async {
    final settings = await _settingsService.loadSettings();
    final country = await _countryLocationService.getCurrentCountryOrFallback();
    CapturedLocation? capturedLocation;
    String? locationLabel;
    if (settings.locationTaggingEnabled) {
      capturedLocation = await _locationCaptureService.captureForObservation();
      if (capturedLocation != null) {
        locationLabel = await _locationLabelService.labelFor(
          latitude: capturedLocation.latitude,
          longitude: capturedLocation.longitude,
          mode: settings.locationLabelMode,
        );
      }
    }
    return _OnlineIdentificationContext(
      country: country,
      region: locationLabel,
      latitude: capturedLocation?.latitude,
      longitude: capturedLocation?.longitude,
      accuracyMeters: capturedLocation?.accuracyMeters,
      capturedAt: capturedLocation?.capturedAt,
      locationLabel: locationLabel,
    );
  }

  Future<_CaptureSelection?> _runCaptureDetectors(NativeYuvFrame frame) async {
    final detections = <Detection>[];
    for (final model in _captureModels) {
      final engine = await _captureEngineFor(model);
      final stopwatch = Stopwatch()..start();
      final nativeDetections = await engine.detectFrame(frame);
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint(
          '[DetectTiming][capture] model=${model.modelId} '
          'inferenceMs=${stopwatch.elapsedMilliseconds} '
          'dets=${nativeDetections.length}',
        );
      }
      detections.addAll(
        _mapNativeDetections(
          model,
          nativeDetections,
          targetInputWidth: _inputWidth,
          targetInputHeight: _inputHeight,
        ),
      );
    }
    final merged = _mergeCrossModelDetections(detections);
    final selection = _selectCaptureDetection(merged);
    if (kDebugMode) {
      debugPrint(
        '[DetectTiming][capture] winnerModel=${selection?.primary.modelId ?? 'none'} '
        'secondaryModel=${selection?.secondary?.modelId ?? 'none'} '
        'ambiguous=${selection?.isAmbiguous ?? false}',
      );
    }
    return selection;
  }

  Future<NativeYoloEngine> _captureEngineFor(
    _YoloModelDescriptor model,
  ) async {
    final existing = _captureEngines[model.modelId];
    if (existing != null) {
      return existing;
    }
    final metadata = _modelMetadata[model.modelId];
    if (metadata == null) {
      throw StateError('Metadata not loaded for ${model.modelId}');
    }
    final modelPath = await _materializeAsset(
      model.modelAssetPath,
      model.materializedFileName,
    );
    final engine = await NativeYoloEngine.create(
      NativeYoloConfig(
        modelPath: modelPath,
        debugLabel: 'capture-${model.modelId}',
        inputWidth: metadata.inputWidth,
        inputHeight: metadata.inputHeight,
        threads: Platform.isAndroid ? 3 : 2,
        maxDetections: 150,
        confidenceThreshold: model.nativeConfidenceThreshold,
        iouThreshold: model.iouThreshold,
        displayConfidenceThreshold: model.displayConfidenceThreshold,
        useGpu: false,
        allowFp16: model.allowFp16,
      ),
    );
    _captureEngines[model.modelId] = engine;
    return engine;
  }

  List<Detection> _mergeCrossModelDetections(List<Detection> detections) {
    if (detections.length < 2) {
      return detections;
    }
    final sorted = [...detections]
      ..sort((a, b) => b.finalScore.compareTo(a.finalScore));
    final used = <int>{};
    final output = <Detection>[];

    for (int i = 0; i < sorted.length; i++) {
      if (used.contains(i)) {
        continue;
      }
      final base = sorted[i];
      final group = <Detection>[base];
      used.add(i);
      for (int j = i + 1; j < sorted.length; j++) {
        if (used.contains(j)) {
          continue;
        }
        final candidate = sorted[j];
        if (base.modelId == candidate.modelId) {
          continue;
        }
        final double overlap = intersectionOverUnion(base.box, candidate.box);
        if (overlap < _crossModelMergeIoUThreshold) {
          _logDualLiveMergeDecision(
            winner: base,
            suppressed: candidate,
            reason: 'low_iou',
            iou: overlap,
          );
          continue;
        }
        _logDualLiveMergeDecision(
          winner: base,
          suppressed: candidate,
          reason: 'overlap_group',
          iou: overlap,
        );
        group.add(candidate);
        used.add(j);
      }
      output.addAll(_mergeDetectionGroup(group));
    }

    output.sort((a, b) => b.finalScore.compareTo(a.finalScore));
    return output;
  }

  List<Detection> _mergeDetectionGroup(List<Detection> group) {
    if (group.length == 1) {
      return group;
    }
    final sorted = [...group]
      ..sort((a, b) => b.finalScore.compareTo(a.finalScore));
    final best = sorted.first;
    final sameSpecies = group.every(
      (candidate) => _normalizeName(candidate.speciesName) ==
          _normalizeName(best.speciesName),
    );
    if (!sameSpecies) {
      if (_dualLiveDebug && group.length > 1) {
        for (final candidate in sorted.skip(1)) {
          _logDualLiveMergeDecision(
            winner: best,
            suppressed: candidate,
            reason: 'different_species_keep_separate',
            iou: intersectionOverUnion(best.box, candidate.box),
          );
        }
      }
      return sorted;
    }
    final sourceModelIds = group.map((d) => d.modelId).toSet().toList()
      ..sort();
    final sourceClassKeys = group
        .map((d) => d.namespacedClassId)
        .toSet()
        .toList()
      ..sort();
    final sourceModelDisplayNames =
        group.map((d) => d.modelDisplayName).toSet().toList()..sort();
    final double averageScore =
        group.fold<double>(0.0, (sum, d) => sum + d.finalScore) / group.length;
    final double finalScore = (averageScore + 0.05).clamp(0.0, 1.0);
    if (_dualLiveDebug) {
      for (final candidate in sorted.skip(1)) {
        _logDualLiveMergeDecision(
          winner: best,
          suppressed: candidate,
          reason: 'same_species_merged',
          iou: intersectionOverUnion(best.box, candidate.box),
        );
      }
    }
    return <Detection>[
      Detection(
        box: best.box,
        confidence: finalScore,
        classId: best.sourceClassId,
        label: best.speciesName,
        modelId: 'merged',
        modelDisplayName: sourceModelDisplayNames.join(' + '),
        sourceClassId: best.sourceClassId,
        namespacedClassId: sourceClassKeys.join('+'),
        speciesName: best.speciesName,
        rawConfidence: best.rawConfidence,
        calibratedConfidence: averageScore,
        finalScore: finalScore,
        sourceModelIds: sourceModelIds,
        sourceModelDisplayNames: <String>['Merged'],
        timestampMs: group
            .map((d) => d.timestampMs)
            .whereType<int>()
            .fold<int?>(null, (latest, value) {
          if (latest == null || value > latest) {
            return value;
          }
          return latest;
        }),
        frameIndex: group
            .map((d) => d.frameIndex)
            .whereType<int>()
            .fold<int?>(null, (latest, value) {
          if (latest == null || value > latest) {
            return value;
          }
          return latest;
        }),
      ),
    ];
  }

  _CaptureSelection? _selectCaptureDetection(List<Detection> detections) {
    if (detections.isEmpty) {
      return null;
    }
    final sorted = [...detections]
      ..sort((a, b) => b.finalScore.compareTo(a.finalScore));
    final primary = sorted.first;
    final candidates = <Detection>[primary];
    bool ambiguous = false;
    for (final candidate in sorted.skip(1)) {
      if (intersectionOverUnion(primary.box, candidate.box) <
          _crossModelMergeIoUThreshold) {
        continue;
      }
      if (candidate.finalScore < _crossModelCompetingMinScore) {
        continue;
      }
      candidates.add(candidate);
      final bool crossModelConflict = primary.modelId != candidate.modelId;
      final double scoreGap =
          (primary.finalScore - candidate.finalScore).abs();
      if (!ambiguous) {
        ambiguous = crossModelConflict &&
              candidate.finalScore >= _crossModelCompetingMinScore
          ? scoreGap < _crossModelOverrideMargin
          : scoreGap < _crossModelAmbiguousMargin;
      }
      if (candidates.length >= 3) {
        break;
      }
    }
    return _CaptureSelection(
      candidates: candidates,
      isAmbiguous: ambiguous,
    );
  }

  void _logDualLiveMergeDecision({
    required Detection winner,
    required Detection suppressed,
    required String reason,
    required double iou,
  }) {
    if (!_dualLiveDebug) {
      return;
    }
    final double scoreGap = winner.finalScore - suppressed.finalScore;
    final bool ambiguous = winner.modelId != suppressed.modelId &&
        suppressed.finalScore >= _crossModelCompetingMinScore &&
        scoreGap.abs() < _crossModelOverrideMargin;
    debugPrint(
      '[DUAL_LIVE] merge winner=${winner.modelId} '
      'suppressed=${suppressed.modelId} reason=$reason '
      'iou=${iou.toStringAsFixed(2)} '
      'scoreGap=${scoreGap.toStringAsFixed(2)} ambiguous=$ambiguous',
    );
  }

  DetectionResultArgs _resultArgsFromTimedScan(
    _CaptureSelection? captureSelection,
    _ScanWindowSummary scanSummary,
    String? photoPath,
  ) {
    if (captureSelection == null) {
      return _uncertainResultArgsFromScan(scanSummary, photoPath);
    }

    final _CaptureSelection rankedSelection =
        _rankCaptureSelectionWithScanWindow(captureSelection, scanSummary);
    final bool accepted =
        rankedSelection.primary.finalScore >= _scanFinalAcceptanceThreshold;
    if (!accepted) {
      return _uncertainResultArgsFromScan(
        scanSummary,
        photoPath,
        possibleCaptureSelection: rankedSelection,
      );
    }

    return _resultArgsFromCaptureSelection(
      rankedSelection,
      _primaryTrack ?? _lastStableTrack,
      photoPath,
      metrics: _metricsForScan(
        scanSummary,
        rankedSelection.primary,
      ),
      isConfirmed: true,
    );
  }

  _CaptureSelection _rankCaptureSelectionWithScanWindow(
    _CaptureSelection selection,
    _ScanWindowSummary scanSummary,
  ) {
    final ranked = selection.candidates
        .map((candidate) => _rankScanCandidate(candidate, scanSummary))
        .toList()
      ..sort((a, b) => b.finalScore.compareTo(a.finalScore));

    final _ScanRankedCandidate primary = ranked.first;
    final _ScanRankedCandidate? secondary = ranked.length > 1 ? ranked[1] : null;
    final bool ambiguous =
        secondary != null &&
        (primary.finalScore - secondary.finalScore).abs() <= _scanSecondaryMargin;
    return _CaptureSelection(
      candidates: ranked
          .take(3)
          .map(
            (candidate) => _detectionWithFinalScore(
              candidate.detection,
              candidate.finalScore,
            ),
          )
          .toList(growable: false),
      isAmbiguous: ambiguous,
    );
  }

  _ScanRankedCandidate _rankScanCandidate(
    Detection detection,
    _ScanWindowSummary scanSummary,
  ) {
    final double liveSupport = scanSummary.supportFor(detection);
    final double finalScore =
        (detection.finalScore * _scanCaptureWeight) +
        (liveSupport * _scanLiveWindowWeight);
    return _ScanRankedCandidate(
      detection: detection,
      liveSupport: liveSupport,
      finalScore: finalScore.clamp(0.0, 1.0),
    );
  }

  Detection _detectionWithFinalScore(Detection detection, double finalScore) {
    return Detection(
      box: detection.box,
      confidence: finalScore,
      classId: detection.classId,
      label: detection.label,
      modelId: detection.modelId,
      modelDisplayName: detection.modelDisplayName,
      sourceClassId: detection.sourceClassId,
      namespacedClassId: detection.namespacedClassId,
      speciesName: detection.speciesName,
      rawConfidence: detection.rawConfidence,
      calibratedConfidence: detection.calibratedConfidence,
      finalScore: finalScore,
      sourceModelIds: detection.sourceModelIds,
      sourceModelDisplayNames: detection.sourceModelDisplayNames,
      timestampMs: detection.timestampMs,
      frameIndex: detection.frameIndex,
    );
  }

  _ResultWindowMetrics _metricsForScan(
    _ScanWindowSummary scanSummary,
    Detection primary,
  ) {
    final support =
        scanSummary.supportByName[_normalizeName(primary.speciesName)];
    final int totalFrames = scanSummary.windowFrameCount;
    final double voteRatio = totalFrames <= 0 || support == null
        ? 0.0
        : support.framesSeen / totalFrames;
    return _ResultWindowMetrics(
      top1VoteRatio: voteRatio.clamp(0.0, 1.0),
      windowFrameCount: totalFrames,
      windowDurationMs: scanSummary.windowDurationMs,
      stabilityWinCount: _primaryTrack?.stabilityWinCount ?? 0,
      stabilityWindowSize: _stabilityEngine.config.stabilityWindowFramesM,
    );
  }

  DetectionResultArgs _resultArgsFromCaptureSelection(
    _CaptureSelection selection,
    StableTrack? fallbackTrack,
    String? photoPath, {
    _ResultWindowMetrics? metrics,
    bool isConfirmed = true,
  }) {
    final primary = selection.primary;
    final candidates = selection.candidates
        .take(3)
        .map(_candidateFromDetection)
        .toList(growable: false);
    final secondary = selection.secondary;
    final resultMetrics = metrics ??
        _ResultWindowMetrics(
          top1VoteRatio: fallbackTrack?.top1VoteRatio ?? 0.0,
          windowFrameCount: fallbackTrack?.windowFrameCount ?? 0,
          windowDurationMs: fallbackTrack?.windowDurationMs ?? 0,
          stabilityWinCount: fallbackTrack?.stabilityWinCount ?? 0,
          stabilityWindowSize: fallbackTrack?.stabilityWindowSize ??
              _stabilityEngine.config.stabilityWindowFramesM,
        );
    final bool isLichen = _isLichenDetection(
      classIndex: primary.sourceClassId,
      label: primary.speciesName,
      modelId: primary.modelId,
    );
    return DetectionResultArgs(
      observationId: null,
      lockedLabel: primary.speciesName,
      top2Label: secondary?.speciesName,
      top2ClassIndex: secondary?.sourceClassId,
      top1AvgConf: primary.finalScore,
      top2AvgConf: secondary?.finalScore,
      top1VoteRatio: resultMetrics.top1VoteRatio,
      windowFrameCount: resultMetrics.windowFrameCount,
      windowDurationMs: resultMetrics.windowDurationMs,
      stabilityWinCount: resultMetrics.stabilityWinCount,
      stabilityWindowSize: resultMetrics.stabilityWindowSize,
      timestamp: DateTime.now(),
      speciesId: _speciesIdForDetection(
        modelId: primary.modelId,
        sourceClassId: primary.sourceClassId,
        label: primary.speciesName,
      ),
      classIndex: primary.sourceClassId,
      photoPath: photoPath,
      isLichen: isLichen,
      modelId: primary.modelId,
      modelDisplayName: primary.sourceDisplayName,
      sourceClassId: primary.sourceClassId,
      rawConfidence: primary.rawConfidence,
      calibratedConfidence: primary.calibratedConfidence,
      finalScore: primary.finalScore,
      top2ModelId: secondary?.modelId,
      top2ModelDisplayName: secondary?.sourceDisplayName,
      top2SourceClassId: secondary?.sourceClassId,
      candidates: candidates,
      isConfirmed: isConfirmed,
    );
  }

  ObservationCandidate _candidateFromDetection(Detection detection) {
    return ObservationCandidate(
      label: detection.speciesName,
      confidence: detection.finalScore,
      classIndex: detection.sourceClassId,
      speciesId: _speciesIdForDetection(
        modelId: detection.modelId,
        sourceClassId: detection.sourceClassId,
        label: detection.speciesName,
      ),
      modelId: detection.modelId,
      modelDisplayName: detection.sourceDisplayName,
      sourceClassId: detection.sourceClassId,
      rawConfidence: detection.rawConfidence,
      calibratedConfidence: detection.calibratedConfidence,
      finalScore: detection.finalScore,
    );
  }

  DetectionResultArgs _uncertainResultArgsFromScan(
    _ScanWindowSummary scanSummary,
    String? photoPath, {
    _CaptureSelection? possibleCaptureSelection,
  }) {
    final rankedSupports = scanSummary.rankedSupports;
    final _ScanWindowSupport? livePossible = rankedSupports.isNotEmpty &&
            rankedSupports.first.supportScore >=
                _scanLivePossibleSupportThreshold
        ? rankedSupports.first
        : null;
    final Detection? capturePossible = possibleCaptureSelection?.primary;
    final String? possibleLabel =
        capturePossible?.speciesName ?? livePossible?.label;
    final double? possibleScore =
        capturePossible?.finalScore ?? livePossible?.supportScore;
    final int? possibleClassIndex =
        capturePossible?.sourceClassId ?? livePossible?.classIndex;
    final String? possibleModelId =
        capturePossible?.modelId ?? livePossible?.modelId;
    final String? possibleModelDisplayName =
        capturePossible?.sourceDisplayName ?? livePossible?.modelDisplayName;
    final double confidence = possibleScore ?? 0.0;
    return DetectionResultArgs(
      observationId: null,
      lockedLabel: 'Uncertain fungus detected',
      top2Label: possibleLabel,
      top2ClassIndex: possibleClassIndex,
      top1AvgConf: confidence,
      top2AvgConf: possibleScore,
      top1VoteRatio: 0.0,
      windowFrameCount: scanSummary.windowFrameCount,
      windowDurationMs: scanSummary.windowDurationMs,
      stabilityWinCount: _primaryTrack?.stabilityWinCount ?? 0,
      stabilityWindowSize: _stabilityEngine.config.stabilityWindowFramesM,
      timestamp: DateTime.now(),
      speciesId: null,
      classIndex: null,
      photoPath: photoPath,
      isLichen: false,
      modelId: null,
      modelDisplayName: 'Unconfirmed',
      sourceClassId: null,
      rawConfidence: confidence,
      calibratedConfidence: confidence,
      finalScore: confidence,
      top2ModelId: possibleModelId,
      top2ModelDisplayName: possibleModelDisplayName,
      top2SourceClassId: possibleClassIndex,
      isConfirmed: false,
    );
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

  ButtonStyle _primaryActionStyle({bool disabledMuted = false}) {
    return ElevatedButton.styleFrom(
      backgroundColor: _highlightGreen,
      foregroundColor: _deepGreen,
      disabledBackgroundColor: disabledMuted
          ? _deepGreen.withValues(alpha: 0.35)
          : _highlightGreen.withValues(alpha: 0.85),
      disabledForegroundColor: disabledMuted ? _mutedWhite : _deepGreen,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: const StadiumBorder(),
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
    if (controller == null ||
        _liveEngines.isEmpty ||
        !controller.value.isInitialized) {
      return;
    }

    await controller.startImageStream((CameraImage image) {
      if (!mounted) return;
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      _streamFrameCount += 1;
      _lastStreamFrameMs = nowMs;
      final rotationDegrees = controller.description.sensorOrientation;
      final frame = NativeYuvFrame.fromCameraImage(
        image,
        rotationDegrees: rotationDegrees,
      );
      _latestFrame = frame;
      final model = _selectLiveModelForFrame();
      final engine = _liveEngines[model.modelId];
      if (engine == null) {
        _liveSkippedFrameCount += 1;
        return;
      }
      _liveSubmittedFrameCountByModel[model.modelId] =
          (_liveSubmittedFrameCountByModel[model.modelId] ?? 0) + 1;
      _liveLatestSubmittedFrameByModel[model.modelId] = _streamFrameCount;
      _logDualLiveFrameSubmission(_streamFrameCount, model);
      _logFrameSubmission(nowMs, model);
      engine.submitFrame(frame);
    });
  }

  _YoloModelDescriptor _selectLiveModelForFrame() {
    final liveModels = _liveModels;
    if (liveModels.length <= 1) {
      return liveModels.first;
    }
    final model = liveModels[_liveAlternatingCursor % liveModels.length];
    _liveAlternatingCursor += 1;
    return model;
  }

  void _logDualLiveFrameSubmission(
    int frameIndex,
    _YoloModelDescriptor model,
  ) {
    if (!_dualLiveDebug) {
      return;
    }
    final metadata = _modelMetadata[model.modelId];
    final String size = metadata == null
        ? 'unknown'
        : '${metadata.inputWidth}x${metadata.inputHeight}';
    debugPrint(
      '[DUAL_LIVE] frame=$frameIndex submitted ${model.modelId} '
      'size=$size path=${model.modelAssetPath}',
    );
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
    _scanCountdownTimer?.cancel();
    _stopStreamAndDispose();
    super.dispose();
  }

  Future<void> _stopStreamAndDispose() async {
    await _disposeCameraController(silently: true);
    await _disposeLiveEngines();
    for (final engine in _captureEngines.values) {
      try {
        await engine.dispose();
      } catch (_) {}
    }
    _captureEngines.clear();
  }

  Future<void> _disposeLiveEngines() async {
    for (final sub in _liveFrameResultSubs.values) {
      await sub.cancel();
    }
    _liveFrameResultSubs.clear();
    for (final sub in _liveErrorSubs.values) {
      await sub.cancel();
    }
    _liveErrorSubs.clear();
    for (final engine in _liveEngines.values) {
      try {
        await engine.dispose();
      } catch (_) {}
    }
    _liveEngines.clear();
    _liveDetectionSnapshots.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _scanCountdownTimer?.cancel();
      _isScanning = false;
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
        title: const Text('Fungi Detection'),
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
                final bool isReady = primaryTrack?.isReadyToCapture ?? false;
                final _DetectionUiPresentation ui = _buildUiPresentation(
                  primaryTrack,
                  DateTime.now().millisecondsSinceEpoch,
                );
                final String statusText = _isScanning
                    ? 'Hold camera steady on the fungus'
                    : ui.statusText;
                final IconData statusIcon =
                    _isScanning ? Icons.hourglass_top : ui.statusIcon;
                final String? bannerTitle = ui.bannerTitle;
                final String? bannerSubtitle = ui.bannerSubtitle;
                final String? bannerDetail = ui.bannerDetail;
                final String? topSpeciesId = ui.speciesId;
                final bool isOnlineMode =
                    _identificationMode == _IdentificationMode.online;
                final String visibleStatusText = _offlinePhotoLoading
                    ? 'Analyzing photo on this device...'
                    : _onlineLoading
                    ? 'Checking with online identification...'
                    : isOnlineMode
                    ? 'Take or select one clear photo'
                    : statusText;
                final IconData visibleStatusIcon = _offlinePhotoLoading
                    ? Icons.image_search
                    : _onlineLoading
                    ? Icons.cloud_sync
                    : isOnlineMode
                    ? Icons.cloud_upload
                    : statusIcon;
                final Color visibleAccent =
                    _offlinePhotoLoading || _onlineLoading || isOnlineMode
                    ? _accentGreen
                    : isReady
                    ? _highlightGreen
                    : (ui.state == _DetectionUiState.lowConfidence
                          ? Colors.orangeAccent
                          : _accentGreen);

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
                                      onTap: !ui.canOpenSpecies ||
                                              topSpeciesId == null
                                          ? null
                                          : () => _openSpeciesDetail(topSpeciesId),
                                    ),
                                  ),
                                const Spacer(),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _IdentificationModeToggle(
                                        value: _identificationMode,
                                        enabled: !_isCapturing &&
                                            !_isScanning &&
                                            !_onlineLoading,
                                        onChanged: (value) {
                                          if (kDebugMode &&
                                              value == _IdentificationMode.online) {
                                            debugPrint(
                                              'ONLINE_ID: online mode selected',
                                            );
                                          }
                                          setState(() {
                                            _identificationMode = value;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      _StatusPill(
                                        text: visibleStatusText,
                                        icon: visibleStatusIcon,
                                        accentColor: visibleAccent,
                                        backgroundColor: _deepGreen.withValues(
                                          alpha: 0.75,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      if (isOnlineMode)
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          spacing: 10,
                                          runSpacing: 8,
                                          children: [
                                            ElevatedButton.icon(
                                              onPressed: (_onlineLoading ||
                                                      _isCapturing ||
                                                      _isScanning)
                                                  ? null
                                                  : _startOnlineIdentificationFromCamera,
                                              icon: const Icon(Icons.camera_alt),
                                              label: Text(
                                                _onlineLoading
                                                    ? 'Checking...'
                                                    : 'Take photo',
                                              ),
                                              style: _primaryActionStyle(),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: (_onlineLoading ||
                                                      _isCapturing ||
                                                      _isScanning)
                                                  ? null
                                                  : _selectOnlineIdentificationPhoto,
                                              icon: const Icon(Icons.photo_library),
                                              label: const Text('Select photo'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: BorderSide(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.6),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 12,
                                                ),
                                                shape: const StadiumBorder(),
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          spacing: 10,
                                          runSpacing: 8,
                                          children: [
                                            ElevatedButton.icon(
                                              onPressed: (_isCapturing ||
                                                      _isScanning ||
                                                      _offlinePhotoLoading)
                                                  ? null
                                                  : _startTimedScan,
                                              icon: Icon(
                                                _isScanning
                                                    ? Icons.hourglass_top
                                                    : Icons.center_focus_strong,
                                              ),
                                              label: Text(
                                                _isScanning
                                                    ? 'Scanning... $_scanRemainingSeconds'
                                                    : 'Live scan',
                                              ),
                                              style: _primaryActionStyle(),
                                            ),
                                            ElevatedButton.icon(
                                              onPressed: (_isCapturing ||
                                                      _isScanning ||
                                                      _offlinePhotoLoading)
                                                  ? null
                                                  : _startOfflineIdentificationFromCamera,
                                              icon: const Icon(Icons.camera_alt),
                                              label: const Text('Take photo'),
                                              style: _primaryActionStyle(),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: (_isCapturing ||
                                                      _isScanning ||
                                                      _offlinePhotoLoading)
                                                  ? null
                                                  : _selectOfflineIdentificationPhoto,
                                              icon: const Icon(Icons.photo_library),
                                              label: const Text('Choose photo'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: BorderSide(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.6),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 12,
                                                ),
                                                shape: const StadiumBorder(),
                                              ),
                                            ),
                                          ],
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

class _IdentificationModeToggle extends StatelessWidget {
  final _IdentificationMode value;
  final bool enabled;
  final ValueChanged<_IdentificationMode> onChanged;

  const _IdentificationModeToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _deepGreen.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accentGreen.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            label: 'Offline',
            icon: Icons.phone_android,
            selected: value == _IdentificationMode.offline,
            enabled: enabled,
            onTap: () => onChanged(_IdentificationMode.offline),
          ),
          _ModeButton(
            label: 'Online',
            icon: Icons.cloud,
            selected: value == _IdentificationMode.online,
            enabled: enabled,
            onTap: () => onChanged(_IdentificationMode.online),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected ? _deepGreen : _mutedWhite;
    final Color background =
        selected ? _highlightGreen : Colors.transparent;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: 15),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
    final Paint labelBackgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xCC1F4E3D);

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

      final TextPainter labelPainter = TextPainter(
        text: TextSpan(
          text: d.overlayLabel,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        maxLines: 2,
        ellipsis: '...',
        textDirection: TextDirection.ltr,
      );
      final double maxLabelWidth = (size.width - left - 8).clamp(80.0, 240.0);
      labelPainter.layout(maxWidth: maxLabelWidth);
      final double labelLeft = left.clamp(0.0, size.width - labelPainter.width - 8);
      final double labelTop = (top - labelPainter.height - 6).clamp(
        0.0,
        size.height - labelPainter.height - 4,
      );
      final Rect labelRect = Rect.fromLTWH(
        labelLeft,
        labelTop,
        labelPainter.width + 8,
        labelPainter.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        labelBackgroundPaint,
      );
      labelPainter.paint(
        canvas,
        Offset(labelLeft + 4, labelTop + 2),
      );
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
