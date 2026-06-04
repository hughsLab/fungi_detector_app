// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import '../detection/detection.dart';
import '../detection/iou.dart';
import '../native/native_yolo_engine.dart';

class DetectionBatchTestRunner {
  static const String model1Folder =
      String.fromEnvironment(
        'DETECTION_BATCH_MODEL1_DIR',
        defaultValue: r'D:\Inatrualist_170_species_global\test\images',
      );
  static const String model2Folder = String.fromEnvironment(
    'DETECTION_BATCH_MODEL2_DIR',
    defaultValue: r'D:\136 species\images\train',
  );
  static const String reportPath = String.fromEnvironment(
    'DETECTION_BATCH_REPORT_PATH',
    defaultValue: r'build\detection_batch_test_report.json',
  );
  static const int imagesPerFolder = 10;
  static const Set<String> acceptedExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
  };

  static const double _confThreshold = 0.30;
  static const double _nmsIoUThreshold = 0.45;
  static const double _displayConfidenceThreshold = 0.45;
  static const double _crossModelMergeIoUThreshold = 0.5;
  static const double _crossModelAmbiguousMargin = 0.20;
  static const double _crossModelOverrideMargin = 0.25;
  static const double _crossModelCompetingMinScore = 0.45;

  static const _BatchModelDescriptor _model1 = _BatchModelDescriptor(
    modelId: 'model_1',
    displayName: 'Model 1',
    modelAssetPath: 'assets/models/1_yolo11n_float32.tflite',
    metadataAssetPath: 'assets/models/metadata_1.yaml',
    materializedFileName: '1_yolo11n_float32.tflite',
  );

  static const _BatchModelDescriptor _model2 = _BatchModelDescriptor(
    modelId: 'model_2',
    displayName: 'Model 2',
    modelAssetPath: 'assets/models/yolo11n_float32.tflite',
    metadataAssetPath: 'assets/models/metadata.yaml',
    materializedFileName: 'yolo11n_float32.tflite',
  );

  final Map<String, _BatchModelMetadata> _metadata =
      <String, _BatchModelMetadata>{};
  final Map<String, NativeYoloEngine> _engines = <String, NativeYoloEngine>{};
  final List<_ConfidenceSample> _confidenceSamples = <_ConfidenceSample>[];
  late int _targetInputWidth;
  late int _targetInputHeight;

  Future<void> runAndExit() async {
    var exitStatus = 0;
    try {
      await run();
    } catch (e, stack) {
      exitStatus = 1;
      print('DETECTION_BATCH_TEST failed: $e');
      print(stack);
      await _writeFailureReport(e, stack);
    } finally {
      await _disposeEngines();
    }
    exit(exitStatus);
  }

  Future<void> run() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final List<_DatasetConfig> datasets = <_DatasetConfig>[
      const _DatasetConfig(
        name: 'model_1_dataset',
        expectedModelId: 'model_1',
        folderPath: model1Folder,
      ),
      const _DatasetConfig(
        name: 'model_2_dataset',
        expectedModelId: 'model_2',
        folderPath: model2Folder,
      ),
    ];

    _printHeader();
    _preflightNativeSupport();
    await _loadMetadata();
    await _createEngines();

    final List<_ImageReport> imageReports = <_ImageReport>[];
    for (final dataset in datasets) {
      final images = _firstValidImages(dataset.folderPath);
      if (images.length != imagesPerFolder) {
        throw StateError(
          'Expected exactly $imagesPerFolder valid images in '
          '${dataset.folderPath}, found ${images.length}.',
        );
      }
      for (final image in images) {
        final report = await _runImage(dataset, image);
        imageReports.add(report);
        _printImageReport(report);
      }
    }

    stopwatch.stop();
    final summary = _buildSummary(imageReports, stopwatch.elapsedMilliseconds);
    await _writeReport(imageReports, summary);
    _printSummary(summary);
  }

  void _printHeader() {
    print('DETECTION_BATCH_TEST=true');
    print('Camera: disabled');
    print('Model binaries: unchanged');
    print('Metadata YAML: unchanged');
    print('Report: $reportPath');
    print('');
  }

  void _preflightNativeSupport() {
    if (!Platform.isWindows) {
      return;
    }
    final candidates = <File>[
      File('yolo_engine.dll'),
      File(r'build\windows\x64\runner\Debug\yolo_engine.dll'),
      File(r'build\windows\x64\runner\Release\yolo_engine.dll'),
      File('${File(Platform.resolvedExecutable).parent.path}\\yolo_engine.dll'),
    ];
    final hasDll = candidates.any((file) => file.existsSync());
    if (hasDll) {
      return;
    }
    throw StateError(
      'Windows native inference is not currently supported in this checkout: '
      'NativeYoloEngine opens yolo_engine.dll on Windows, but no '
      'yolo_engine.dll was found next to the executable or in common build '
      'outputs. The Windows CMake files do not add native/yolo_engine or link '
      'TensorFlow Lite for this DLL, while the Android CMake path does build '
      'the native engine against android/app/src/main/jniLibs.',
    );
  }

  Future<void> _loadMetadata() async {
    final model1Metadata = await _loadModelMetadata(_model1.metadataAssetPath);
    final model2Metadata = await _loadModelMetadata(_model2.metadataAssetPath);
    _metadata[_model1.modelId] = model1Metadata;
    _metadata[_model2.modelId] = model2Metadata;
    _targetInputWidth = model2Metadata.inputWidth;
    _targetInputHeight = model2Metadata.inputHeight;
    print(
      'Loaded metadata: Model 1 labels=${model1Metadata.labels.length} '
      'input=${model1Metadata.inputWidth}x${model1Metadata.inputHeight}; '
      'Model 2 labels=${model2Metadata.labels.length} '
      'input=${model2Metadata.inputWidth}x${model2Metadata.inputHeight}',
    );
  }

  Future<_BatchModelMetadata> _loadModelMetadata(String assetPath) async {
    final yamlStr = await rootBundle.loadString(assetPath);
    final doc = loadYaml(yamlStr);
    var inputWidth = 640;
    var inputHeight = 640;
    var labels = <String>[];

    if (doc is YamlMap) {
      final size = _inputShapeFromMetadata(doc);
      if (size != null) {
        inputWidth = size.width;
        inputHeight = size.height;
      }
      dynamic namesNode = doc['names'];
      if (namesNode == null && doc['model'] is YamlMap) {
        final modelNode = doc['model'] as YamlMap;
        final modelSize = _inputShapeFromMetadata(modelNode);
        if (modelSize != null) {
          inputWidth = modelSize.width;
          inputHeight = modelSize.height;
        }
        namesNode = modelNode['names'];
      }
      labels = _labelsFromYaml(namesNode);
    }

    if (labels.isEmpty) {
      throw StateError('No class labels found in $assetPath');
    }
    if (labels.any((label) => label.trim().isEmpty)) {
      throw StateError('Metadata labels contain empty entries in $assetPath');
    }
    return _BatchModelMetadata(
      labels: labels,
      inputWidth: inputWidth,
      inputHeight: inputHeight,
    );
  }

  _InputShape? _inputShapeFromMetadata(YamlMap source) {
    final imgsz = source['imgsz'];
    if (imgsz is YamlList && imgsz.isNotEmpty) {
      if (imgsz.length >= 2 && imgsz[0] is num && imgsz[1] is num) {
        return _InputShape(
          width: (imgsz[0] as num).toInt(),
          height: (imgsz[1] as num).toInt(),
        );
      }
      if (imgsz.length == 1 && imgsz[0] is num) {
        final size = (imgsz[0] as num).toInt();
        return _InputShape(width: size, height: size);
      }
    }
    return null;
  }

  List<String> _labelsFromYaml(dynamic namesNode) {
    if (namesNode is YamlList) {
      return namesNode.map((entry) => entry.toString()).toList();
    }
    if (namesNode is! YamlMap) {
      return const <String>[];
    }
    final keys = namesNode.entries
        .map((entry) {
          final key = entry.key;
          return key is int ? key : int.tryParse(key.toString());
        })
        .whereType<int>()
        .toList()
      ..sort();
    if (keys.isEmpty) {
      return const <String>[];
    }
    final filled = List<String>.filled(keys.last + 1, '');
    for (final entry in namesNode.entries) {
      final key = entry.key;
      final index = key is int ? key : int.tryParse(key.toString());
      if (index == null || index < 0 || index >= filled.length) {
        continue;
      }
      filled[index] = entry.value.toString();
    }
    return filled;
  }

  Future<void> _createEngines() async {
    for (final model in <_BatchModelDescriptor>[_model1, _model2]) {
      final metadata = _metadata[model.modelId];
      if (metadata == null) {
        throw StateError('Metadata not loaded for ${model.modelId}');
      }
      final modelPath = await _materializeAsset(
        model.modelAssetPath,
        model.materializedFileName,
      );
      _engines[model.modelId] = await NativeYoloEngine.create(
        NativeYoloConfig(
          modelPath: modelPath,
          inputWidth: metadata.inputWidth,
          inputHeight: metadata.inputHeight,
          threads: Platform.isAndroid ? 3 : 2,
          maxDetections: 150,
          confidenceThreshold: _confThreshold,
          iouThreshold: _nmsIoUThreshold,
          displayConfidenceThreshold: _displayConfidenceThreshold,
          useGpu: false,
          allowFp16: true,
        ),
      );
      print('Loaded ${model.displayName}: $modelPath');
    }
    print('');
  }

  Future<String> _materializeAsset(String assetPath, String fileName) async {
    final directory = Directory(r'build\detection_batch_test_models');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final file = File('${directory.path}\\$fileName');
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.absolute.path;
  }

  List<File> _firstValidImages(String folderPath) {
    final directory = Directory(folderPath);
    if (!directory.existsSync()) {
      throw StateError('Dataset folder not found: $folderPath');
    }
    final files = directory
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => acceptedExtensions.contains(_extension(file.path)))
        .toList()
      ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return files.take(imagesPerFolder).toList(growable: false);
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) {
      return '';
    }
    return path.substring(dot).toLowerCase();
  }

  Future<_ImageReport> _runImage(_DatasetConfig dataset, File image) async {
    final frame = await _decodeImageToYuvFrame(image);
    final rawDetections = <Detection>[];
    for (final model in <_BatchModelDescriptor>[_model1, _model2]) {
      final engine = _engines[model.modelId];
      if (engine == null) {
        throw StateError('Engine not loaded for ${model.modelId}');
      }
      final nativeDetections = await engine.detectFrame(frame);
      final detections = _mapNativeDetections(model, nativeDetections);
      rawDetections.addAll(detections);
      _confidenceSamples.addAll(
        detections.map(
          (detection) => _ConfidenceSample(
            modelId: model.modelId,
            rawConfidence: detection.rawConfidence,
            finalScore: detection.finalScore,
          ),
        ),
      );
    }

    final mergedDetections = _mergeCrossModelDetections(rawDetections);
    final selection = _selectDetection(mergedDetections);
    final dominance = _buildDominance(dataset.expectedModelId, rawDetections);
    final outcome = _outcomeForSelection(selection);

    return _ImageReport(
      datasetName: dataset.name,
      expectedModelId: dataset.expectedModelId,
      imagePath: image.path,
      detectionsFound: rawDetections.length,
      mergedDetectionsFound: mergedDetections.length,
      outcome: outcome,
      selected: selection?.primary,
      secondary: selection?.secondary,
      isAmbiguous: selection?.isAmbiguous ?? false,
      topDetections: mergedDetections.take(5).toList(growable: false),
      dominance: dominance,
    );
  }

  Future<NativeYuvFrame> _decodeImageToYuvFrame(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (byteData == null) {
      throw StateError('Unable to decode image bytes: ${imageFile.path}');
    }
    final rgba = byteData.buffer.asUint8List();
    return _rgbaToYuvFrame(rgba, image.width, image.height);
  }

  NativeYuvFrame _rgbaToYuvFrame(Uint8List rgba, int width, int height) {
    final yBytes = Uint8List(width * height);
    final uvWidth = (width + 1) >> 1;
    final uvHeight = (height + 1) >> 1;
    final uBytes = Uint8List(uvWidth * uvHeight);
    final vBytes = Uint8List(uvWidth * uvHeight);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final rgbIndex = (y * width + x) * 4;
        final r = rgba[rgbIndex];
        final g = rgba[rgbIndex + 1];
        final b = rgba[rgbIndex + 2];
        yBytes[y * width + x] = _clampToByte(
          (0.299 * r + 0.587 * g + 0.114 * b).round(),
        );
      }
    }

    for (var blockY = 0; blockY < uvHeight; blockY++) {
      for (var blockX = 0; blockX < uvWidth; blockX++) {
        var uSum = 0.0;
        var vSum = 0.0;
        var count = 0;
        for (var dy = 0; dy < 2; dy++) {
          final y = blockY * 2 + dy;
          if (y >= height) {
            continue;
          }
          for (var dx = 0; dx < 2; dx++) {
            final x = blockX * 2 + dx;
            if (x >= width) {
              continue;
            }
            final rgbIndex = (y * width + x) * 4;
            final r = rgba[rgbIndex];
            final g = rgba[rgbIndex + 1];
            final b = rgba[rgbIndex + 2];
            uSum += -0.168736 * r - 0.331264 * g + 0.5 * b + 128.0;
            vSum += 0.5 * r - 0.418688 * g - 0.081312 * b + 128.0;
            count++;
          }
        }
        final uvIndex = blockY * uvWidth + blockX;
        uBytes[uvIndex] = _clampToByte((uSum / count).round());
        vBytes[uvIndex] = _clampToByte((vSum / count).round());
      }
    }

    return NativeYuvFrame(
      width: width,
      height: height,
      rotationDegrees: 0,
      yRowStride: width,
      uvRowStride: uvWidth,
      uvPixelStride: 1,
      yBytes: yBytes,
      uBytes: uBytes,
      vBytes: vBytes,
    );
  }

  int _clampToByte(int value) {
    return math.max(0, math.min(255, value));
  }

  List<Detection> _mapNativeDetections(
    _BatchModelDescriptor model,
    List<NativeDetection> detections,
  ) {
    final metadata = _metadata[model.modelId];
    if (metadata == null) {
      return const <Detection>[];
    }
    final scaleX = _targetInputWidth / metadata.inputWidth;
    final scaleY = _targetInputHeight / metadata.inputHeight;
    return detections.map((detection) {
      final label = _labelForIndex(detection.classIndex, model);
      final finalScore = detection.score.clamp(0.0, 1.0);
      return Detection(
        box: ui.Rect.fromLTRB(
          detection.left * scaleX,
          detection.top * scaleY,
          detection.right * scaleX,
          detection.bottom * scaleY,
        ),
        confidence: finalScore,
        classId: detection.classIndex,
        label: label,
        modelId: model.modelId,
        modelDisplayName: model.displayName,
        sourceClassId: detection.classIndex,
        namespacedClassId: '${model.modelId}:${detection.classIndex}',
        speciesName: label,
        rawConfidence: detection.score,
        calibratedConfidence: finalScore,
        finalScore: finalScore,
        sourceModelIds: <String>[model.modelId],
        sourceModelDisplayNames: <String>[model.displayName],
      );
    }).toList(growable: false);
  }

  String _labelForIndex(int index, _BatchModelDescriptor model) {
    final labels = _metadata[model.modelId]?.labels;
    if (labels != null && index >= 0 && index < labels.length) {
      final label = labels[index].trim();
      if (label.isNotEmpty) {
        return label;
      }
    }
    return 'Unknown';
  }

  List<Detection> _mergeCrossModelDetections(List<Detection> detections) {
    if (detections.length < 2) {
      return detections;
    }
    final sorted = [...detections]
      ..sort((a, b) => b.finalScore.compareTo(a.finalScore));
    final used = <int>{};
    final output = <Detection>[];

    for (var i = 0; i < sorted.length; i++) {
      if (used.contains(i)) {
        continue;
      }
      final base = sorted[i];
      final group = <Detection>[base];
      used.add(i);
      for (var j = i + 1; j < sorted.length; j++) {
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
      (candidate) =>
          _normalizeName(candidate.speciesName) ==
          _normalizeName(best.speciesName),
    );
    if (!sameSpecies) {
      return sorted;
    }
    final sourceModelIds = group.map((d) => d.modelId).toSet().toList()
      ..sort();
    final sourceModelDisplayNames =
        group.map((d) => d.modelDisplayName).toSet().toList()..sort();
    final averageScore =
        group.fold<double>(0.0, (sum, d) => sum + d.finalScore) / group.length;
    final finalScore = (averageScore + 0.05).clamp(0.0, 1.0);
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

  _BatchSelection? _selectDetection(List<Detection> detections) {
    if (detections.isEmpty) {
      return null;
    }
    final sorted = [...detections]
      ..sort((a, b) => b.finalScore.compareTo(a.finalScore));
    final primary = sorted.first;
    Detection? secondary;
    var ambiguous = false;
    for (final candidate in sorted.skip(1)) {
      if (intersectionOverUnion(primary.box, candidate.box) <
          _crossModelMergeIoUThreshold) {
        continue;
      }
      secondary = candidate;
      final crossModelConflict = primary.modelId != candidate.modelId;
      final scoreGap = (primary.finalScore - candidate.finalScore).abs();
      ambiguous = crossModelConflict &&
              candidate.finalScore >= _crossModelCompetingMinScore
          ? scoreGap < _crossModelOverrideMargin
          : scoreGap < _crossModelAmbiguousMargin;
      break;
    }
    return _BatchSelection(
      primary: primary,
      secondary: secondary,
      isAmbiguous: ambiguous,
    );
  }

  _ModelDominance _buildDominance(
    String expectedModelId,
    List<Detection> rawDetections,
  ) {
    Detection? bestModel1;
    Detection? bestModel2;
    for (final detection in rawDetections) {
      if (detection.modelId == _model1.modelId &&
          (bestModel1 == null ||
              detection.finalScore > bestModel1.finalScore)) {
        bestModel1 = detection;
      }
      if (detection.modelId == _model2.modelId &&
          (bestModel2 == null ||
              detection.finalScore > bestModel2.finalScore)) {
        bestModel2 = detection;
      }
    }
    final expectedBest =
        expectedModelId == _model1.modelId ? bestModel1 : bestModel2;
    final unexpectedBest =
        expectedModelId == _model1.modelId ? bestModel2 : bestModel1;
    final margin =
        (unexpectedBest?.finalScore ?? 0.0) - (expectedBest?.finalScore ?? 0.0);
    return _ModelDominance(
      bestModel1: bestModel1,
      bestModel2: bestModel2,
      dominanceMargin: margin,
      wrongModelDominates: unexpectedBest != null &&
          margin > 0 &&
          unexpectedBest.modelId != expectedModelId,
    );
  }

  String _outcomeForSelection(_BatchSelection? selection) {
    if (selection == null) {
      return 'unknown';
    }
    if (selection.isAmbiguous) {
      return 'ambiguous';
    }
    if (selection.primary.modelId == 'merged') {
      return 'merged';
    }
    if (selection.primary.modelId == _model1.modelId) {
      return 'model_1';
    }
    if (selection.primary.modelId == _model2.modelId) {
      return 'model_2';
    }
    return 'unknown';
  }

  String _normalizeName(String value) {
    final normalized = value.trim().toLowerCase().replaceAll('_', ' ');
    return normalized.replaceAll(RegExp(r'\s+'), ' ');
  }

  void _printImageReport(_ImageReport report) {
    final selected = report.selected;
    final secondary = report.secondary;
    print('IMAGE ${report.imagePath}');
    print('  expectedModel=${report.expectedModelId}');
    print(
      '  detectionsFound=${report.detectionsFound} '
      'mergedDetectionsFound=${report.mergedDetectionsFound}',
    );
    print('  selectedModel=${selected?.sourceDisplayName ?? 'Unknown'}');
    print('  modelId=${selected?.modelId ?? 'unknown'}');
    print('  sourceClassId=${selected?.sourceClassId.toString() ?? 'unknown'}');
    print('  speciesName=${selected?.speciesName ?? 'Unknown'}');
    print('  rawConfidence=${_formatDouble(selected?.rawConfidence)}');
    print('  finalScore=${_formatDouble(selected?.finalScore)}');
    print('  result=${report.outcome}');
    if (secondary != null) {
      print(
        '  competing=${secondary.modelId}:${secondary.sourceClassId} '
        '${secondary.speciesName} finalScore='
        '${_formatDouble(secondary.finalScore)}',
      );
    }
    print(
      '  dominance bestModel1=${_formatDetection(report.dominance.bestModel1)} '
      'bestModel2=${_formatDetection(report.dominance.bestModel2)} '
      'wrongModelDominates=${report.dominance.wrongModelDominates} '
      'margin=${_formatDouble(report.dominance.dominanceMargin)}',
    );
    print('');
  }

  String _formatDetection(Detection? detection) {
    if (detection == null) {
      return 'none';
    }
    return '${detection.modelId}:${detection.sourceClassId} '
        '${_formatDouble(detection.finalScore)}';
  }

  String _formatDouble(double? value) {
    if (value == null) {
      return 'unknown';
    }
    return value.toStringAsFixed(4);
  }

  _BatchSummary _buildSummary(
    List<_ImageReport> reports,
    int elapsedMilliseconds,
  ) {
    final model1Images =
        reports.where((report) => report.expectedModelId == _model1.modelId);
    final model2Images =
        reports.where((report) => report.expectedModelId == _model2.modelId);
    final wrongDominanceCases = reports
        .where((report) => report.dominance.wrongModelDominates)
        .toList(growable: false);
    return _BatchSummary(
      elapsedMilliseconds: elapsedMilliseconds,
      model1DatasetImages: model1Images.length,
      model2DatasetImages: model2Images.length,
      model1Wins: reports
          .where((report) => report.selected?.modelId == _model1.modelId)
          .length,
      model2Wins: reports
          .where((report) => report.selected?.modelId == _model2.modelId)
          .length,
      mergedWins:
          reports.where((report) => report.selected?.modelId == 'merged').length,
      ambiguousResults:
          reports.where((report) => report.outcome == 'ambiguous').length,
      unknownResults:
          reports.where((report) => report.outcome == 'unknown').length,
      averageConfidenceByModel: _averageConfidenceByModel(),
      wrongDominanceCases: wrongDominanceCases,
    );
  }

  Map<String, _AverageConfidence> _averageConfidenceByModel() {
    final grouped = <String, List<_ConfidenceSample>>{};
    for (final sample in _confidenceSamples) {
      grouped.putIfAbsent(sample.modelId, () => <_ConfidenceSample>[]).add(
            sample,
          );
    }
    return grouped.map((modelId, samples) {
      final rawAverage = samples.fold<double>(
            0.0,
            (sum, sample) => sum + sample.rawConfidence,
          ) /
          samples.length;
      final finalAverage = samples.fold<double>(
            0.0,
            (sum, sample) => sum + sample.finalScore,
          ) /
          samples.length;
      return MapEntry(
        modelId,
        _AverageConfidence(
          detectionCount: samples.length,
          rawConfidence: rawAverage,
          finalScore: finalAverage,
        ),
      );
    });
  }

  Future<void> _writeReport(
    List<_ImageReport> reports,
    _BatchSummary summary,
  ) async {
    final file = File(reportPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final payload = <String, dynamic>{
      'createdAt': DateTime.now().toIso8601String(),
      'cameraUsed': false,
      'modelBinariesAltered': false,
      'metadataYamlAltered': false,
      'datasets': <Map<String, dynamic>>[
        {
          'name': 'model_1_dataset',
          'expectedModelId': 'model_1',
          'folderPath': model1Folder,
          'imagesRequested': imagesPerFolder,
        },
        {
          'name': 'model_2_dataset',
          'expectedModelId': 'model_2',
          'folderPath': model2Folder,
          'imagesRequested': imagesPerFolder,
        },
      ],
      'summary': summary.toJson(),
      'images': reports.map((report) => report.toJson()).toList(),
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }

  Future<void> _writeFailureReport(Object error, StackTrace stack) async {
    final file = File(reportPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final payload = <String, dynamic>{
      'createdAt': DateTime.now().toIso8601String(),
      'cameraUsed': false,
      'status': 'failed',
      'error': error.toString(),
      'stackTrace': stack.toString(),
      'windowsNativeInferenceNote': Platform.isWindows
          ? 'NativeYoloEngine opens yolo_engine.dll on Windows. This checkout '
              'does not build/install that DLL from windows/CMakeLists.txt.'
          : null,
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }

  void _printSummary(_BatchSummary summary) {
    print('SUMMARY');
    print('  model_1_dataset_images=${summary.model1DatasetImages}');
    print('  model_2_dataset_images=${summary.model2DatasetImages}');
    print('  model_1_wins=${summary.model1Wins}');
    print('  model_2_wins=${summary.model2Wins}');
    print('  merged_wins=${summary.mergedWins}');
    print('  ambiguous_results=${summary.ambiguousResults}');
    print('  unknown_no_detection_results=${summary.unknownResults}');
    for (final entry in summary.averageConfidenceByModel.entries) {
      print(
        '  avg_confidence_${entry.key}=raw:'
        '${_formatDouble(entry.value.rawConfidence)} final:'
        '${_formatDouble(entry.value.finalScore)} '
        'detections:${entry.value.detectionCount}',
      );
    }
    print('  wrong_model_dominance_cases=${summary.wrongDominanceCases.length}');
    for (final report in summary.wrongDominanceCases) {
      print(
        '    ${report.expectedModelId} image dominated by wrong model: '
        '${report.imagePath} margin='
        '${_formatDouble(report.dominance.dominanceMargin)}',
      );
    }
    print('  elapsed_ms=${summary.elapsedMilliseconds}');
    print('');
    print('Wrote $reportPath');
  }

  Future<void> _disposeEngines() async {
    for (final engine in _engines.values) {
      await engine.dispose();
    }
    _engines.clear();
  }
}

class _BatchModelDescriptor {
  const _BatchModelDescriptor({
    required this.modelId,
    required this.displayName,
    required this.modelAssetPath,
    required this.metadataAssetPath,
    required this.materializedFileName,
  });

  final String modelId;
  final String displayName;
  final String modelAssetPath;
  final String metadataAssetPath;
  final String materializedFileName;
}

class _BatchModelMetadata {
  const _BatchModelMetadata({
    required this.labels,
    required this.inputWidth,
    required this.inputHeight,
  });

  final List<String> labels;
  final int inputWidth;
  final int inputHeight;
}

class _InputShape {
  const _InputShape({required this.width, required this.height});

  final int width;
  final int height;
}

class _DatasetConfig {
  const _DatasetConfig({
    required this.name,
    required this.expectedModelId,
    required this.folderPath,
  });

  final String name;
  final String expectedModelId;
  final String folderPath;
}

class _BatchSelection {
  const _BatchSelection({
    required this.primary,
    required this.secondary,
    required this.isAmbiguous,
  });

  final Detection primary;
  final Detection? secondary;
  final bool isAmbiguous;
}

class _ModelDominance {
  const _ModelDominance({
    required this.bestModel1,
    required this.bestModel2,
    required this.dominanceMargin,
    required this.wrongModelDominates,
  });

  final Detection? bestModel1;
  final Detection? bestModel2;
  final double dominanceMargin;
  final bool wrongModelDominates;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'bestModel1': _detectionSummaryToJson(bestModel1),
      'bestModel2': _detectionSummaryToJson(bestModel2),
      'dominanceMargin': dominanceMargin,
      'wrongModelDominates': wrongModelDominates,
    };
  }
}

class _ImageReport {
  const _ImageReport({
    required this.datasetName,
    required this.expectedModelId,
    required this.imagePath,
    required this.detectionsFound,
    required this.mergedDetectionsFound,
    required this.outcome,
    required this.selected,
    required this.secondary,
    required this.isAmbiguous,
    required this.topDetections,
    required this.dominance,
  });

  final String datasetName;
  final String expectedModelId;
  final String imagePath;
  final int detectionsFound;
  final int mergedDetectionsFound;
  final String outcome;
  final Detection? selected;
  final Detection? secondary;
  final bool isAmbiguous;
  final List<Detection> topDetections;
  final _ModelDominance dominance;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'datasetName': datasetName,
      'expectedModelId': expectedModelId,
      'imagePath': imagePath,
      'detectionsFound': detectionsFound,
      'mergedDetectionsFound': mergedDetectionsFound,
      'selectedModel': selected?.sourceDisplayName ?? 'Unknown',
      'modelId': selected?.modelId ?? 'unknown',
      'sourceClassId': selected?.sourceClassId,
      'speciesName': selected?.speciesName ?? 'Unknown',
      'rawConfidence': selected?.rawConfidence,
      'finalScore': selected?.finalScore,
      'result': outcome,
      'isAmbiguous': isAmbiguous,
      'secondary': _detectionSummaryToJson(secondary),
      'dominance': dominance.toJson(),
      'topDetections': topDetections.map(_detectionSummaryToJson).toList(),
    };
  }
}

class _ConfidenceSample {
  const _ConfidenceSample({
    required this.modelId,
    required this.rawConfidence,
    required this.finalScore,
  });

  final String modelId;
  final double rawConfidence;
  final double finalScore;
}

class _AverageConfidence {
  const _AverageConfidence({
    required this.detectionCount,
    required this.rawConfidence,
    required this.finalScore,
  });

  final int detectionCount;
  final double rawConfidence;
  final double finalScore;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'detectionCount': detectionCount,
      'rawConfidence': rawConfidence,
      'finalScore': finalScore,
    };
  }
}

class _BatchSummary {
  const _BatchSummary({
    required this.elapsedMilliseconds,
    required this.model1DatasetImages,
    required this.model2DatasetImages,
    required this.model1Wins,
    required this.model2Wins,
    required this.mergedWins,
    required this.ambiguousResults,
    required this.unknownResults,
    required this.averageConfidenceByModel,
    required this.wrongDominanceCases,
  });

  final int elapsedMilliseconds;
  final int model1DatasetImages;
  final int model2DatasetImages;
  final int model1Wins;
  final int model2Wins;
  final int mergedWins;
  final int ambiguousResults;
  final int unknownResults;
  final Map<String, _AverageConfidence> averageConfidenceByModel;
  final List<_ImageReport> wrongDominanceCases;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'elapsedMilliseconds': elapsedMilliseconds,
      'model1DatasetImages': model1DatasetImages,
      'model2DatasetImages': model2DatasetImages,
      'model1Wins': model1Wins,
      'model2Wins': model2Wins,
      'mergedWins': mergedWins,
      'ambiguousResults': ambiguousResults,
      'unknownNoDetectionResults': unknownResults,
      'averageConfidenceByModel': averageConfidenceByModel.map(
        (modelId, average) => MapEntry(modelId, average.toJson()),
      ),
      'wrongModelDominanceCases': wrongDominanceCases
          .map(
            (report) => <String, dynamic>{
              'imagePath': report.imagePath,
              'expectedModelId': report.expectedModelId,
              'result': report.outcome,
              'selected': _detectionSummaryToJson(report.selected),
              'dominance': report.dominance.toJson(),
            },
          )
          .toList(),
    };
  }
}

Map<String, dynamic>? _detectionSummaryToJson(Detection? detection) {
  if (detection == null) {
    return null;
  }
  return <String, dynamic>{
    'modelId': detection.modelId,
    'modelDisplayName': detection.sourceDisplayName,
    'sourceClassId': detection.sourceClassId,
    'namespacedClassId': detection.namespacedClassId,
    'speciesName': detection.speciesName,
    'rawConfidence': detection.rawConfidence,
    'calibratedConfidence': detection.calibratedConfidence,
    'finalScore': detection.finalScore,
    'sourceModelIds': detection.sourceModelIds,
    'sourceModelDisplayNames': detection.sourceModelDisplayNames,
    'box': <String, double>{
      'left': detection.box.left,
      'top': detection.box.top,
      'right': detection.box.right,
      'bottom': detection.box.bottom,
    },
  };
}
