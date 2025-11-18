#include "postprocess.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

namespace yolo {

namespace {

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
    return empty;
  }

  int num_boxes = 0;
  int channels = 0;
  bool channels_first = false;

  if (shape.size() == 3) {
    const int dim1 = shape[1];
    const int dim2 = shape[2];
    if (dim1 <= dim2 && (dim1 == 84 || dim1 == 85 || (dim1 > 4 && dim1 < 200))) {
      channels = dim1;
      num_boxes = dim2;
      channels_first = true;
    } else {
      channels = dim2;
      num_boxes = dim1;
      channels_first = false;
    }
  } else {
    const int dim2 = shape[2];
    const int dim3 = shape[3];
    if (dim2 == 84 || dim2 == 85 || (dim2 > 4 && dim2 < 200)) {
      channels = dim2;
      num_boxes = dim3;
      channels_first = true;
    } else {
      channels = dim3;
      num_boxes = dim2;
      channels_first = false;
    }
  }

  if (channels <= 0 || num_boxes <= 0) {
    return empty;
  }

  const bool has_objectness = channels >= 85;
  const int num_classes = has_objectness ? channels - 5 : channels - 4;
  std::vector<YoloDetection> candidates;
  candidates.reserve(std::min(num_boxes, options.max_detections * 2));

  for (int i = 0; i < num_boxes; ++i) {
    float cx = 0.0f;
    float cy = 0.0f;
    float w = 0.0f;
    float h = 0.0f;
    float objectness = 1.0f;
    int best_class = -1;
    float best_score = -std::numeric_limits<float>::infinity();

    if (channels_first) {
      const int base = i;
      cx = tensor[0 * num_boxes + base];
      cy = tensor[1 * num_boxes + base];
      w = tensor[2 * num_boxes + base];
      h = tensor[3 * num_boxes + base];
      if (has_objectness) {
        objectness = tensor[4 * num_boxes + base];
      }
      const int class_start = has_objectness ? 5 : 4;
      for (int c = 0; c < num_classes; ++c) {
        const float cls_score = tensor[(class_start + c) * num_boxes + base];
        if (cls_score > best_score) {
          best_score = cls_score;
          best_class = c;
        }
      }
    } else {
      const int base = i * channels;
      cx = tensor[base + 0];
      cy = tensor[base + 1];
      w = tensor[base + 2];
      h = tensor[base + 3];
      if (has_objectness) {
        objectness = tensor[base + 4];
      }
      const int class_start = has_objectness ? 5 : 4;
      for (int c = 0; c < num_classes; ++c) {
        const float cls_score = tensor[base + class_start + c];
        if (cls_score > best_score) {
          best_score = cls_score;
          best_class = c;
        }
      }
    }

    const float combined_score = has_objectness ? objectness * best_score : best_score;
    if (combined_score < options.confidence_threshold) {
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
    det.score = combined_score;
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
