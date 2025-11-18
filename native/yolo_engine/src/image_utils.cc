#include "image_utils.h"

#include <algorithm>
#include <cmath>

#include "yolo_engine.h"

namespace yolo {

namespace {
inline uint8_t ClampToByte(int value) {
  if (value < 0) return 0;
  if (value > 255) return 255;
  return static_cast<uint8_t>(value);
}
}  // namespace

void Yuv420ToRgb(const FrameMetadata& frame, std::vector<uint8_t>* rgb_target) {
  if (rgb_target == nullptr) {
    return;
  }
  const int width = frame.width;
  const int height = frame.height;
  const size_t required = static_cast<size_t>(width) * static_cast<size_t>(height) * 3;
  rgb_target->assign(required, 0);

  for (int y = 0; y < height; ++y) {
    const int y_row_index = frame.y_row_stride * y;
    const int uv_row_index = frame.uv_row_stride * (y >> 1);
    for (int x = 0; x < width; ++x) {
      const int y_index = y_row_index + x;
      const int uv_index = uv_row_index + (x >> 1) * frame.uv_pixel_stride;

      const double yf = static_cast<double>(frame.y_plane[y_index]);
      const double uf = static_cast<double>(frame.u_plane[uv_index]) - 128.0;
      const double vf = static_cast<double>(frame.v_plane[uv_index]) - 128.0;

      int r = static_cast<int>(std::round(yf + 1.402 * vf));
      int g = static_cast<int>(std::round(yf - 0.344136 * uf - 0.714136 * vf));
      int b = static_cast<int>(std::round(yf + 1.772 * uf));

      const size_t rgb_index = (static_cast<size_t>(y) * width + x) * 3;
      (*rgb_target)[rgb_index] = ClampToByte(r);
      (*rgb_target)[rgb_index + 1] = ClampToByte(g);
      (*rgb_target)[rgb_index + 2] = ClampToByte(b);
    }
  }
}

void RotateRgb(const std::vector<uint8_t>& src, int width, int height, int rotation_degrees,
               std::vector<uint8_t>* dst) {
  if (dst == nullptr) {
    return;
  }
  const int normalized_rotation = ((rotation_degrees % 360) + 360) % 360;
  if (normalized_rotation == 0) {
    *dst = src;
    return;
  }

  const int channels = 3;
  int dst_width = width;
  int dst_height = height;
  if (normalized_rotation == 90 || normalized_rotation == 270) {
    dst_width = height;
    dst_height = width;
  }
  dst->assign(static_cast<size_t>(dst_width) * dst_height * channels, 0);

  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      int dst_x = x;
      int dst_y = y;
      switch (normalized_rotation) {
        case 90:
          dst_x = height - 1 - y;
          dst_y = x;
          break;
        case 180:
          dst_x = width - 1 - x;
          dst_y = height - 1 - y;
          break;
        case 270:
          dst_x = y;
          dst_y = width - 1 - x;
          break;
        default:
          dst_x = x;
          dst_y = y;
          break;
      }

      const size_t src_index = (static_cast<size_t>(y) * width + x) * channels;
      const size_t dst_index = (static_cast<size_t>(dst_y) * dst_width + dst_x) * channels;
      (*dst)[dst_index] = src[src_index];
      (*dst)[dst_index + 1] = src[src_index + 1];
      (*dst)[dst_index + 2] = src[src_index + 2];
    }
  }
}

void ResizeAndNormalize(const std::vector<uint8_t>& src, int src_width, int src_height,
                        int dst_width, int dst_height, std::vector<float>* dst) {
  if (dst == nullptr || src.empty() || src_width <= 0 || src_height <= 0 || dst_width <= 0 ||
      dst_height <= 0) {
    return;
  }
  const int channels = 3;
  dst->assign(static_cast<size_t>(dst_width) * dst_height * channels, 0.0f);

  const float scale_x = static_cast<float>(src_width) / static_cast<float>(dst_width);
  const float scale_y = static_cast<float>(src_height) / static_cast<float>(dst_height);

  for (int y = 0; y < dst_height; ++y) {
    const float src_y = (y + 0.5f) * scale_y - 0.5f;
    const int y0 = std::clamp(static_cast<int>(std::floor(src_y)), 0, src_height - 1);
    const int y1 = std::clamp(y0 + 1, 0, src_height - 1);
    const float y_lerp = src_y - static_cast<float>(y0);

    for (int x = 0; x < dst_width; ++x) {
      const float src_x = (x + 0.5f) * scale_x - 0.5f;
      const int x0 = std::clamp(static_cast<int>(std::floor(src_x)), 0, src_width - 1);
      const int x1 = std::clamp(x0 + 1, 0, src_width - 1);
      const float x_lerp = src_x - static_cast<float>(x0);

      const size_t top_left = (static_cast<size_t>(y0) * src_width + x0) * channels;
      const size_t top_right = (static_cast<size_t>(y0) * src_width + x1) * channels;
      const size_t bottom_left = (static_cast<size_t>(y1) * src_width + x0) * channels;
      const size_t bottom_right = (static_cast<size_t>(y1) * src_width + x1) * channels;

      const size_t dst_index = (static_cast<size_t>(y) * dst_width + x) * channels;
      for (int c = 0; c < channels; ++c) {
        const float top = static_cast<float>(src[top_left + c]) +
                          (static_cast<float>(src[top_right + c]) -
                           static_cast<float>(src[top_left + c])) *
                              x_lerp;
        const float bottom = static_cast<float>(src[bottom_left + c]) +
                             (static_cast<float>(src[bottom_right + c]) -
                              static_cast<float>(src[bottom_left + c])) *
                                 x_lerp;
        const float value = top + (bottom - top) * y_lerp;
        (*dst)[dst_index + c] = value / 255.0f;
      }
    }
  }
}

}  // namespace yolo
