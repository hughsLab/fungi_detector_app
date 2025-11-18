#pragma once

#include <cstdint>
#include <vector>

namespace yolo {

struct FrameMetadata;

void Yuv420ToRgb(const FrameMetadata& frame, std::vector<uint8_t>* rgb_target);
void RotateRgb(const std::vector<uint8_t>& src, int width, int height, int rotation_degrees,
               std::vector<uint8_t>* dst);
void ResizeAndNormalize(const std::vector<uint8_t>& src, int src_width, int src_height,
                        int dst_width, int dst_height, std::vector<float>* dst);

}  // namespace yolo
