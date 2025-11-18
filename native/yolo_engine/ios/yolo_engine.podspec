Pod::Spec.new do |s|
  s.name             = 'YoloEngine'
  s.version          = '0.1.0'
  s.summary          = 'Native TensorFlow Lite YOLO pipeline'
  s.description      = <<-DESC
    High-performance TensorFlow Lite based YOLO inference engine with native preprocessing and post-processing.
  DESC
  s.homepage         = 'https://example.com/yolo_engine'
  s.license          = { :type => 'BSD' }
  s.author           = { 'RealtimeDetectionApp' => 'dev@example.com' }
  s.platform         = :ios, '13.0'
  s.source           = { :path => '.' }
  s.requires_arc     = false

  s.source_files     = '../include/**/*.{h}', '../src/**/*.{cc,h}'
  s.public_header_files = '../include/**/*.h'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../src" "$(PODS_TARGET_SRCROOT)/../../../third_party/tflite_flutter/src"'
  }

  s.compiler_flags = '-std=c++17 -fvisibility=hidden'

  s.dependency 'TensorFlowLiteC'
  s.dependency 'TensorFlowLiteGpu'
end
