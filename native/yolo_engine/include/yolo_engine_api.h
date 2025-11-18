#pragma once

#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

struct YoloDetection {
  float left;
  float top;
  float right;
  float bottom;
  float score;
  int32_t class_index;
};

struct YoloDetections {
  YoloDetection* detections;
  int32_t count;
};

void* YoloEngineCreate(const char* model_path,
                       int32_t input_width,
                       int32_t input_height,
                       int32_t num_threads,
                       int32_t max_detections,
                       float confidence_threshold,
                       float iou_threshold,
                       int32_t use_gpu,
                       int32_t allow_fp16);

void YoloEngineDestroy(void* handle);

int32_t YoloEngineProcessYuvFrame(void* handle,
                                  const uint8_t* y_plane,
                                  const uint8_t* u_plane,
                                  const uint8_t* v_plane,
                                  int32_t y_row_stride,
                                  int32_t uv_row_stride,
                                  int32_t uv_pixel_stride,
                                  int32_t width,
                                  int32_t height,
                                  int32_t rotation_degrees,
                                  YoloDetections* out);

void YoloEngineReleaseDetections(YoloDetections* detections);

#ifdef __cplusplus
}
#endif
