# Realtime Detection App

Flutter application that renders the camera preview at 60 FPS while pushing all
YOLO preprocessing, TensorFlow Lite inference, and post-processing into a
native C++ pipeline that is shared by Android and iOS through `dart:ffi`.

## Architecture

- `lib/native/native_yolo_engine.dart` hosts a dedicated isolate that feeds
  camera frames to the native engine via FFI, drops intermediate frames, and
  streams lightweight detection results back to Flutter.
- `native/yolo_engine` contains the shared C++ code. It converts YUV420 frames
  to RGB, applies bilinear resizing and normalization, runs TensorFlow Lite
  through the C API, and performs native NMS/decoding.
- Android builds the engine through CMake (`android/app/src/main/cpp`) and
  links against `org.tensorflow:tensorflow-lite` + GPU delegate via Prefab.
- iOS consumes the exact same sources via the local CocoaPod
  `native/yolo_engine/ios/yolo_engine.podspec` which depends on
  `TensorFlowLiteC` and the Metal delegate.

Flutter never touches raw frame data anymore. The UI draws the camera texture
and paints the bounding boxes received from the native isolate.

## Prerequisites

- Flutter 3.24+ with Dart 3.8 SDK
- Android Studio / NDK r27 (configured via `android/app/build.gradle.kts`)
- Xcode 15 with CocoaPods for iOS builds

## Setup

```bash
flutter pub get

# Android (first run downloads the NDK toolchain automatically)
flutter run -d android

# iOS
cd ios
pod install
cd ..
flutter run -d ios
```

The Android build will compile `native/yolo_engine` into `libyolo_engine.so`.
For iOS the CocoaPods integration builds the same code directly into the Runner
target, so FFI loads the symbols via `DynamicLibrary.process()`.

## Next Steps

- Tune model resolution / thresholds inside `NativeYoloConfig`
- Toggle GPU delegation per-platform if needed
- Add performance telemetry to compare CPU vs GPU delegates
