#include "yolo_engine_api.h"

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

#include "yolo_engine.h"

namespace {

inline yolo::YoloEngine* AsEngine(void* handle) {
  return reinterpret_cast<yolo::YoloEngine*>(handle);
}

}  // namespace

extern "C" {

void* YoloEngineCreate(const char* model_path, int32_t input_width, int32_t input_height,
                       int32_t num_threads, int32_t max_detections, float confidence_threshold,
                       float iou_threshold, int32_t use_gpu, int32_t allow_fp16) {
  if (model_path == nullptr) {
    return nullptr;
  }
  yolo::EngineOptions options;
  options.input_width = input_width;
  options.input_height = input_height;
  options.num_threads = std::max(1, num_threads);
  options.max_detections = std::max(1, max_detections);
  options.confidence_threshold = confidence_threshold;
  options.iou_threshold = iou_threshold;
  options.use_gpu = use_gpu != 0;
  options.allow_fp16 = allow_fp16 != 0;

  auto engine = yolo::YoloEngine::Create(model_path, options);
  return engine ? engine.release() : nullptr;
}

void YoloEngineDestroy(void* handle) {
  delete AsEngine(handle);
}

int32_t YoloEngineProcessYuvFrame(void* handle, const uint8_t* y_plane, const uint8_t* u_plane,
                                  const uint8_t* v_plane, int32_t y_row_stride, int32_t uv_row_stride,
                                  int32_t uv_pixel_stride, int32_t width, int32_t height,
                                  int32_t rotation_degrees, YoloDetections* out) {
  if (handle == nullptr || y_plane == nullptr || u_plane == nullptr || v_plane == nullptr ||
      out == nullptr) {
    return -1;
  }
  yolo::FrameMetadata frame{y_plane,      u_plane,        v_plane,       width,
                            height,       y_row_stride,   uv_row_stride, uv_pixel_stride,
                            rotation_degrees};
  auto* engine = AsEngine(handle);
  std::vector<YoloDetection> detections;
  if (!engine->ProcessFrame(frame, &detections)) {
    return -2;
  }

  if (detections.empty()) {
    out->detections = nullptr;
    out->count = 0;
    return 0;
  }

  auto* buffer = new YoloDetection[detections.size()];
  for (size_t i = 0; i < detections.size(); ++i) {
    buffer[i] = detections[i];
  }
  out->detections = buffer;
  out->count = static_cast<int32_t>(detections.size());
  return 0;
}

void YoloEngineReleaseDetections(YoloDetections* detections) {
  if (detections == nullptr || detections->detections == nullptr) {
    return;
  }
  delete[] detections->detections;
  detections->detections = nullptr;
  detections->count = 0;
}

}  // extern "C"
