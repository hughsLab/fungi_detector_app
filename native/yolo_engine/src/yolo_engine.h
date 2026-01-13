#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "tensorflow_lite/c_api.h"
#include "yolo_engine_api.h"

namespace yolo {

struct EngineOptions {
  int input_width = 640;
  int input_height = 640;
  int num_threads = 2;
  int max_detections = 100;
  float confidence_threshold = 0.3f;
  float iou_threshold = 0.45f;
  bool use_gpu = false;
  bool allow_fp16 = true;
};

struct FrameMetadata {
  const uint8_t* y_plane;
  const uint8_t* u_plane;
  const uint8_t* v_plane;
  int width;
  int height;
  int y_row_stride;
  int uv_row_stride;
  int uv_pixel_stride;
  int rotation_degrees;
};

class YoloEngine {
 public:
  static std::unique_ptr<YoloEngine> Create(const std::string& model_path,
                                            const EngineOptions& options);
  ~YoloEngine();

  bool ProcessFrame(const FrameMetadata& frame, std::vector<YoloDetection>* detections);

 private:
  YoloEngine(EngineOptions options, TfLiteModel* model,
             TfLiteInterpreterOptions* interpreter_options, TfLiteInterpreter* interpreter);

  bool InitializeDelegates();
  bool PrepareInput(const FrameMetadata& frame, std::vector<float>* input_buffer);
  bool InvokeInterpreter(const std::vector<float>& input_buffer, std::vector<float>* output_buffer,
                         std::vector<int>* output_shape);

  EngineOptions options_;
  TfLiteModel* model_ = nullptr;
  TfLiteInterpreterOptions* interpreter_options_ = nullptr;
  TfLiteInterpreter* interpreter_ = nullptr;
  TfLiteDelegate* gpu_delegate_ = nullptr;
  std::vector<uint8_t> rgb_buffer_;
  std::vector<uint8_t> rotated_buffer_;
  bool logged_shapes_ = false;
};

}  // namespace yolo
