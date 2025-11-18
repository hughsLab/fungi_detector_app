#pragma once

#include <vector>

#include "yolo_engine.h"

namespace yolo {

std::vector<YoloDetection> DecodeDetections(const std::vector<float>& tensor,
                                            const std::vector<int>& shape,
                                            const EngineOptions& options);

}  // namespace yolo
