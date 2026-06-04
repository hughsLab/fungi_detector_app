import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yaml/yaml.dart';

import '../detection/detection.dart';
import '../detection/iou.dart';
import '../detection/stability_engine.dart';
import '../models/species.dart';
import '../models/navigation_args.dart';
import '../native/native_yolo_engine.dart';
import '../repositories/species_repository.dart';

const Color _deepGreen = Color(0xFF1F4E3D);
const Color _accentGreen = Color(0xFF8FBFA1);
const Color _highlightGreen = Color(0xFF7CD39A);
const Color _mutedWhite = Color(0xCCFFFFFF);

enum _DetectionUiState {
  scanning,
  possibleMatch,
  confirming,
  matchFound,
  lowConfidence,
}

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
  final Detection primary;
  final Detection? secondary;
  final bool isAmbiguous;

  const _CaptureSelection({
    required this.primary,
    required this.secondary,
    required this.isAmbiguous,
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
  NativeYoloEngine? _nativeEngine;
  StreamSubscription<List<NativeDetection>>? _nativeDetectionsSub;
  StreamSubscription<String>? _nativeErrorSub;
  late DetectionStabilityEngine _stabilityEngine;
  List<String> _labels = [];
  final Map<String, _ModelMetadata> _modelMetadata =
      <String, _ModelMetadata>{};
  final Map<String, NativeYoloEngine> _captureEngines =
      <String, NativeYoloEngine>{};
  NativeYuvFrame? _latestFrame;
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;
  Map<String, String> _speciesIdByName = {};
  Map<String, String> _speciesIdByModelClass = {};
  Set<int> _lichenClassIndices = <int>{};
  Set<String> _lichenClassKeys = <String>{};
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
  StableTrack? _lastStableTrack;
  int _lastStableTrackMs = 0;
  String? _errorMessage;
  int _streamFrameCount = 0;
  int _nativeResultCount = 0;
  int _lastStreamFrameMs = 0;
  int _lastDebugTimingLogMs = 0;
  String? _lastDebugUiState;
  static const int _uiHoldGraceMs = 1300;

  static const double _confThreshold = 0.30;
  static const double _nmsIoUThreshold = 0.45;
  static const double _crossModelMergeIoUThreshold = 0.5;
  static const double _crossModelAmbiguousMargin = 0.20;
  static const double _crossModelOverrideMargin = 0.25;
  static const double _crossModelCompetingMinScore = 0.45;

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

  Future<void> _initializeNativeEngine() async {
    final modelPath = await _materializeAsset(
      _model2.modelAssetPath,
      _model2.materializedFileName,
    );
    final config = NativeYoloConfig(
      modelPath: modelPath,
      inputWidth: _inputWidth,
      inputHeight: _inputHeight,
      threads: Platform.isAndroid ? 3 : 2,
      maxDetections: 150,
      confidenceThreshold: _model2.nativeConfidenceThreshold,
      iouThreshold: _model2.iouThreshold,
      displayConfidenceThreshold: _model2.displayConfidenceThreshold,
      useGpu: _model2.useGpu,
      allowFp16: _model2.allowFp16,
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
    _nativeResultCount += 1;
    final List<Detection> mapped = _mapNativeDetections(
      _model2,
      detections,
      targetInputWidth: _inputWidth,
      targetInputHeight: _inputHeight,
    );
    final List<StableTrack> stableTracks = _stabilityEngine.processFrame(
      mapped,
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
      frameDetectionCount: mapped.length,
      primaryTrack: primaryTrack,
    );
    setState(() {
      _detections = mapped;
      _primaryTrack = primaryTrack;
    });
  }

  List<Detection> _mapNativeDetections(
    _YoloModelDescriptor model,
    List<NativeDetection> detections, {
    required int targetInputWidth,
    required int targetInputHeight,
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
    final normalized = value.trim().toLowerCase().replaceAll('_', ' ');
    return normalized.replaceAll(RegExp(r'\s+'), ' ');
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

  void _logFrameSubmission(int nowMs) {
    if (!kDebugMode) {
      return;
    }
    if (nowMs - _lastDebugTimingLogMs < 1200) {
      return;
    }
    _lastDebugTimingLogMs = nowMs;
    debugPrint(
      '[DetectTiming][ui] frame-received ts=$nowMs submitted=1 streamFrames=$_streamFrameCount nativeResults=$_nativeResultCount',
    );
  }

  void _logDetectionTiming({
    required int nowMs,
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
    final double confidence = primaryTrack?.top1AvgConf ?? 0.0;
    final int wins = primaryTrack?.stabilityWinCount ?? 0;
    final int requiredWins = primaryTrack?.requiredWinsForStability ?? 0;
    final int consecutiveWins = primaryTrack?.consecutiveTop1Wins ?? 0;
    debugPrint(
      '[DetectTiming][ui] inference-return ts=$nowMs frameToResultMs=$approxFrameToResultMs '
      'dets=$frameDetectionCount label="$label" conf=${confidence.toStringAsFixed(3)} '
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
            ? 'Match found: $label'
            : 'Match found: $label ($modelDisplayName)',
        statusIcon: Icons.check_circle,
        bannerTitle: label,
        bannerSubtitle: topConfidence == null
            ? 'Ready to capture'
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
            ? 'Match found: $label'
            : 'Match found: $label ($modelDisplayName)',
        statusIcon: Icons.shield_outlined,
        bannerTitle: label,
        bannerSubtitle: topConfidence == null
            ? 'Confirming...'
            : 'Confirming... $sourceText',
        bannerDetail: ambiguous && active?.top2Label != null
            ? 'Also possible: ${active!.top2Label}'
            : null,
        speciesId: speciesId,
        canOpenSpecies: speciesId != null,
      );
    }

    if (primaryTrack != null && primaryTrack.isProvisional && label != null) {
      final bool mediumOrHigher =
          primaryTrack.top1AvgConf >= _stabilityEngine.config.adaptiveMediumConfMin;
      return _DetectionUiPresentation(
        state: mediumOrHigher
            ? _DetectionUiState.confirming
            : _DetectionUiState.possibleMatch,
        displayTrack: active,
        statusText: mediumOrHigher
            ? 'Confirming...'
            : modelDisplayName == null
                ? 'Possible match: $label'
                : 'Possible match: $label ($modelDisplayName)',
        statusIcon: mediumOrHigher ? Icons.timelapse : Icons.search,
        bannerTitle: mediumOrHigher ? 'Confirming...' : 'Possible match: $label',
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

  Future<void> _handleCapture(StableTrack track) async {
    if (_isCapturing) {
      return;
    }
    setState(() {
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

      final args = captureSelection == null
          ? _resultArgsFromTrack(track, photoPath)
          : _resultArgsFromCaptureSelection(
              captureSelection,
              track,
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
        });
      }
    }
  }

  Future<_CaptureSelection?> _runCaptureDetectors(NativeYuvFrame frame) async {
    final detections = <Detection>[];
    for (final model in _captureModels) {
      final engine = await _captureEngineFor(model);
      final nativeDetections = await engine.detectFrame(frame);
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
    return _selectCaptureDetection(merged);
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
        if (intersectionOverUnion(base.box, candidate.box) <
            _crossModelMergeIoUThreshold) {
          continue;
        }
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
      return sorted;
    }
    final sourceModelIds = group.map((d) => d.modelId).toSet().toList()
      ..sort();
    final sourceModelDisplayNames =
        group.map((d) => d.modelDisplayName).toSet().toList()..sort();
    final double averageScore =
        group.fold<double>(0.0, (sum, d) => sum + d.finalScore) / group.length;
    final double finalScore = (averageScore + 0.05).clamp(0.0, 1.0);
    return <Detection>[
      Detection(
        box: best.box,
        confidence: finalScore,
        classId: best.sourceClassId,
        label: best.speciesName,
        modelId: 'merged',
        modelDisplayName: sourceModelDisplayNames.join(' + '),
        sourceClassId: best.sourceClassId,
        namespacedClassId: sourceModelIds.join('+'),
        speciesName: best.speciesName,
        rawConfidence: best.rawConfidence,
        calibratedConfidence: averageScore,
        finalScore: finalScore,
        sourceModelIds: sourceModelIds,
        sourceModelDisplayNames: sourceModelDisplayNames,
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
    Detection? secondary;
    bool ambiguous = false;
    for (final candidate in sorted.skip(1)) {
      if (intersectionOverUnion(primary.box, candidate.box) <
          _crossModelMergeIoUThreshold) {
        continue;
      }
      secondary = candidate;
      final bool crossModelConflict = primary.modelId != candidate.modelId;
      final double scoreGap =
          (primary.finalScore - candidate.finalScore).abs();
      ambiguous = crossModelConflict &&
              candidate.finalScore >= _crossModelCompetingMinScore
          ? scoreGap < _crossModelOverrideMargin
          : scoreGap < _crossModelAmbiguousMargin;
      break;
    }
    return _CaptureSelection(
      primary: primary,
      secondary: secondary,
      isAmbiguous: ambiguous,
    );
  }

  DetectionResultArgs _resultArgsFromCaptureSelection(
    _CaptureSelection selection,
    StableTrack fallbackTrack,
    String? photoPath,
  ) {
    final primary = selection.primary;
    final secondary = selection.isAmbiguous ? selection.secondary : null;
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
      top1VoteRatio: fallbackTrack.top1VoteRatio,
      windowFrameCount: fallbackTrack.windowFrameCount,
      windowDurationMs: fallbackTrack.windowDurationMs,
      stabilityWinCount: fallbackTrack.stabilityWinCount,
      stabilityWindowSize: fallbackTrack.stabilityWindowSize,
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
    );
  }

  DetectionResultArgs _resultArgsFromTrack(
    StableTrack track,
    String? photoPath,
  ) {
    final int? classIndex = track.lockedClassId ?? track.top1ClassId;
    final String label = track.lockedLabel ??
        track.top1Label ??
        (classIndex == null ? 'Unknown' : _labelForIndex(classIndex));
    final bool isLichen = _isLichenDetection(
      classIndex: classIndex,
      label: label,
      modelId: track.lockedModelId ?? track.top1ModelId,
    );
    return DetectionResultArgs(
      observationId: null,
      lockedLabel: label,
      top2Label: track.isAmbiguous ? track.top2Label : null,
      top2ClassIndex: track.isAmbiguous ? track.top2ClassId : null,
      top1AvgConf: track.lockedClassKey == null
          ? track.top1AvgConf
          : track.lockedAvgConf,
      top2AvgConf: track.isAmbiguous ? track.top2AvgConf : null,
      top1VoteRatio: track.top1VoteRatio,
      windowFrameCount: track.windowFrameCount,
      windowDurationMs: track.windowDurationMs,
      stabilityWinCount: track.stabilityWinCount,
      stabilityWindowSize: track.stabilityWindowSize,
      timestamp: DateTime.now(),
      speciesId: _speciesIdForDetection(
        modelId: track.lockedModelId ?? track.top1ModelId,
        sourceClassId: classIndex,
        label: label,
      ),
      classIndex: classIndex,
      photoPath: photoPath,
      isLichen: isLichen,
      modelId: track.lockedModelId ?? track.top1ModelId,
      modelDisplayName:
          track.lockedModelDisplayName ?? track.top1ModelDisplayName,
      sourceClassId: classIndex,
      rawConfidence: track.lockedClassKey == null
          ? track.top1AvgConf
          : track.lockedAvgConf,
      calibratedConfidence: track.lockedClassKey == null
          ? track.top1AvgConf
          : track.lockedAvgConf,
      finalScore: track.lockedClassKey == null
          ? track.top1AvgConf
          : track.lockedAvgConf,
      top2ModelId: track.isAmbiguous ? track.top2ModelId : null,
      top2ModelDisplayName:
          track.isAmbiguous ? track.top2ModelDisplayName : null,
      top2SourceClassId: track.isAmbiguous ? track.top2ClassId : null,
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
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      _streamFrameCount += 1;
      _lastStreamFrameMs = nowMs;
      _logFrameSubmission(nowMs);
      final rotationDegrees = controller.description.sensorOrientation;
      final frame = NativeYuvFrame.fromCameraImage(
        image,
        rotationDegrees: rotationDegrees,
      );
      _latestFrame = frame;
      engine.submitFrame(frame);
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
    for (final engine in _captureEngines.values) {
      try {
        await engine.dispose();
      } catch (_) {}
    }
    _captureEngines.clear();
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
                final bool isReady = primaryTrack?.isReadyToCapture ?? false;
                final _DetectionUiPresentation ui = _buildUiPresentation(
                  primaryTrack,
                  DateTime.now().millisecondsSinceEpoch,
                );
                final String statusText = ui.statusText;
                final IconData statusIcon = ui.statusIcon;
                final String? bannerTitle = ui.bannerTitle;
                final String? bannerSubtitle = ui.bannerSubtitle;
                final String? bannerDetail = ui.bannerDetail;
                final String? topSpeciesId = ui.speciesId;

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
                                      _StatusPill(
                                        text: statusText,
                                        icon: statusIcon,
                                        accentColor: isReady
                                            ? _highlightGreen
                                            : (ui.state == _DetectionUiState.lowConfidence
                                                  ? Colors.orangeAccent
                                                  : _accentGreen),
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
