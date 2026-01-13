#include "postprocess.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
#include <sstream>
#include <string>
#include <utility>

#if defined(__ANDROID__)
#include <android/log.h>
#endif

namespace yolo {

namespace {

constexpr char kLogTag[] = "YoloEngine";

void LogMessage(const std::string& message) {
#if defined(__ANDROID__)
  __android_log_print(ANDROID_LOG_INFO, kLogTag, "%s", message.c_str());
#else
  std::fprintf(stderr, "%s\n", message.c_str());
#endif
}

std::string ShapeToString(const std::vector<int>& shape) {
  std::ostringstream out;
  out << '[';
  for (size_t i = 0; i < shape.size(); ++i) {
    if (i > 0) {
      out << ',';
    }
    out << shape[i];
  }
  out << ']';
  return out.str();
}

float Clamp(float value, float minimum, float maximum) {
  if (value < minimum) return minimum;
  if (value > maximum) return maximum;
  return value;
}

float ComputeIoU(const YoloDetection& a, const YoloDetection& b) {
  const float inter_left = std::max(a.left, b.left);
  const float inter_top = std::max(a.top, b.top);
  const float inter_right = std::min(a.right, b.right);
  const float inter_bottom = std::min(a.bottom, b.bottom);
  const float inter_width = std::max(0.0f, inter_right - inter_left);
  const float inter_height = std::max(0.0f, inter_bottom - inter_top);
  const float inter_area = inter_width * inter_height;
  const float area_a = (a.right - a.left) * (a.bottom - a.top);
  const float area_b = (b.right - b.left) * (b.bottom - b.top);
  const float denom = area_a + area_b - inter_area + 1e-6f;
  return denom <= 0.0f ? 0.0f : inter_area / denom;
}

}  // namespace

std::vector<YoloDetection> DecodeDetections(const std::vector<float>& tensor,
                                            const std::vector<int>& shape,
                                            const EngineOptions& options) {
  std::vector<YoloDetection> empty;
  if (tensor.empty()) {
    return empty;
  }
  if (shape.size() != 3 && shape.size() != 4) {
    LogMessage("decode: unsupported outputTensorShape=" + ShapeToString(shape));
    return empty;
  }

  int channels = 0;
  int num_pred = 0;

  if (shape.size() == 3) {
    channels = shape[1];
    num_pred = shape[2];
  } else if (shape.size() == 4 && shape[1] == 1) {
    channels = shape[2];
    num_pred = shape[3];
  } else if (shape.size() == 4 && shape[3] == 1) {
    channels = shape[1];
    num_pred = shape[2];
  }

  if (channels < 5 || num_pred <= 0) {
    std::ostringstream log;
    log << "decode: invalid outputTensorShape=" << ShapeToString(shape)
        << " channels=" << channels << " numPred=" << num_pred;
    LogMessage(log.str());
    return empty;
  }

  const int num_classes = channels - 4;
  if (num_classes <= 0) {
    std::ostringstream log;
    log << "decode: invalid numClasses=" << num_classes
        << " from outputTensorShape=" << ShapeToString(shape);
    LogMessage(log.str());
    return empty;
  }

  const size_t expected_size = static_cast<size_t>(channels) * static_cast<size_t>(num_pred);
  if (tensor.size() < expected_size) {
    std::ostringstream log;
    log << "decode: outputTensor too small (size=" << tensor.size()
        << " expected>=" << expected_size << ") for outputTensorShape="
        << ShapeToString(shape);
    LogMessage(log.str());
    return empty;
  }

  const int loop_pred_count = num_pred;
  {
    std::ostringstream log;
    log << "decode: outputTensorShape=" << ShapeToString(shape)
        << " channels=" << channels
        << " numPred=" << num_pred
        << " numClasses=" << num_classes
        << " loopBound=" << loop_pred_count;
    LogMessage(log.str());
  }

  std::vector<YoloDetection> candidates;
  candidates.reserve(std::min(loop_pred_count, options.max_detections * 2));

  for (int i = 0; i < loop_pred_count; ++i) {
    float cx = 0.0f;
    float cy = 0.0f;
    float w = 0.0f;
    float h = 0.0f;
    int best_class = -1;
    float best_score = -std::numeric_limits<float>::infinity();

    const int base = i;
    cx = tensor[0 * loop_pred_count + base];
    cy = tensor[1 * loop_pred_count + base];
    w = tensor[2 * loop_pred_count + base];
    h = tensor[3 * loop_pred_count + base];
    const int class_start = 4;
    for (int c = 0; c < num_classes; ++c) {
      const float cls_score = tensor[(class_start + c) * loop_pred_count + base];
      if (cls_score > best_score) {
        best_score = cls_score;
        best_class = c;
      }
    }

    if (best_score < options.confidence_threshold) {
      continue;
    }

    const bool normalized =
        std::fabs(cx) <= 1.5f && std::fabs(cy) <= 1.5f && w <= 1.5f && h <= 1.5f;
    const float scale_x = normalized ? static_cast<float>(options.input_width) : 1.0f;
    const float scale_y = normalized ? static_cast<float>(options.input_height) : 1.0f;

    const float bx = cx * scale_x - 0.5f * w * scale_x;
    const float by = cy * scale_y - 0.5f * h * scale_y;
    const float bw = w * scale_x;
    const float bh = h * scale_y;

    YoloDetection det;
    det.left = Clamp(bx, 0.0f, static_cast<float>(options.input_width));
    det.top = Clamp(by, 0.0f, static_cast<float>(options.input_height));
    det.right = Clamp(bx + bw, 0.0f, static_cast<float>(options.input_width));
    det.bottom = Clamp(by + bh, 0.0f, static_cast<float>(options.input_height));
    det.score = best_score;
    det.class_index = best_class;
    candidates.push_back(det);
  }

  if (candidates.empty()) {
    return candidates;
  }

  std::sort(candidates.begin(), candidates.end(),
            [](const YoloDetection& a, const YoloDetection& b) { return a.score > b.score; });

  std::vector<YoloDetection> results;
  results.reserve(std::min(static_cast<int>(candidates.size()), options.max_detections));
  std::vector<bool> suppressed(candidates.size(), false);

  for (size_t i = 0; i < candidates.size(); ++i) {
    if (suppressed[i]) {
      continue;
    }
    results.push_back(candidates[i]);
    if (static_cast<int>(results.size()) >= options.max_detections) {
      break;
    }
    for (size_t j = i + 1; j < candidates.size(); ++j) {
      if (suppressed[j]) {
        continue;
      }
      if (candidates[j].class_index != candidates[i].class_index) {
        continue;
      }
      const float iou = ComputeIoU(candidates[i], candidates[j]);
      if (iou > options.iou_threshold) {
        suppressed[j] = true;
      }
    }
  }

  return results;
}

}  // namespace yolo
