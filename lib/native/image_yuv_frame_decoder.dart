import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'native_yolo_engine.dart';

/// Decodes a still image into the YUV420 format used by the embedded models.
class ImageYuvFrameDecoder {
  const ImageYuvFrameDecoder._();

  static Future<NativeYuvFrame> decodeFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Selected photo is no longer available.');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Selected photo is empty.');
    }

    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final decodedFrame = await codec.getNextFrame();
      final image = decodedFrame.image;
      try {
        final width = image.width;
        final height = image.height;
        final byteData = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (byteData == null) {
          throw StateError('Unable to read the selected photo.');
        }
        return rgbaToYuvFrame(
          byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          ),
          width,
          height,
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  static NativeYuvFrame rgbaToYuvFrame(
    Uint8List rgba,
    int width,
    int height,
  ) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      throw ArgumentError('Invalid RGBA image dimensions.');
    }

    final yBytes = Uint8List(width * height);
    final uvWidth = (width + 1) >> 1;
    final uvHeight = (height + 1) >> 1;
    final uBytes = Uint8List(uvWidth * uvHeight);
    final vBytes = Uint8List(uvWidth * uvHeight);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final rgbaIndex = (y * width + x) * 4;
        final r = rgba[rgbaIndex];
        final g = rgba[rgbaIndex + 1];
        final b = rgba[rgbaIndex + 2];
        yBytes[y * width + x] = _clampToByte(
          (0.299 * r + 0.587 * g + 0.114 * b).round(),
        );
      }
    }

    for (var blockY = 0; blockY < uvHeight; blockY++) {
      for (var blockX = 0; blockX < uvWidth; blockX++) {
        var uSum = 0.0;
        var vSum = 0.0;
        var sampleCount = 0;
        for (var offsetY = 0; offsetY < 2; offsetY++) {
          final y = blockY * 2 + offsetY;
          if (y >= height) continue;
          for (var offsetX = 0; offsetX < 2; offsetX++) {
            final x = blockX * 2 + offsetX;
            if (x >= width) continue;
            final rgbaIndex = (y * width + x) * 4;
            final r = rgba[rgbaIndex];
            final g = rgba[rgbaIndex + 1];
            final b = rgba[rgbaIndex + 2];
            uSum += -0.168736 * r - 0.331264 * g + 0.5 * b + 128.0;
            vSum += 0.5 * r - 0.418688 * g - 0.081312 * b + 128.0;
            sampleCount++;
          }
        }
        final uvIndex = blockY * uvWidth + blockX;
        uBytes[uvIndex] = _clampToByte((uSum / sampleCount).round());
        vBytes[uvIndex] = _clampToByte((vSum / sampleCount).round());
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

  static int _clampToByte(int value) => value.clamp(0, 255).toInt();
}
