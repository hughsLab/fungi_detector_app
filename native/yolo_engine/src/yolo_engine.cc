#include "yolo_engine.h"

#include <algorithm>
#include <memory>
#include <utility>
#include <vector>

#include "image_utils.h"
#include "postprocess.h"

#if defined(__ANDROID__)
#include "tensorflow_lite/delegate.h"
#include "tensorflow_lite/delegate_options.h"
#elif defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IOS
#include "tensorflow_lite/metal_delegate.h"
#endif
#endif

namespace yolo {

YoloEngine::YoloEngine(EngineOptions options, TfLiteModel* model,
                       TfLiteInterpreterOptions* interpreter_options, TfLiteInterpreter* interpreter)
    : options_(options),
      model_(model),
      interpreter_options_(interpreter_options),
      interpreter_(interpreter) {}

YoloEngine::~YoloEngine() {
#if defined(__ANDROID__)
  if (gpu_delegate_ != nullptr) {
    TfLiteGpuDelegateV2Delete(gpu_delegate_);
    gpu_delegate_ = nullptr;
  }
#elif defined(__APPLE__) && TARGET_OS_IOS
  if (gpu_delegate_ != nullptr) {
    TFLGpuDelegateDelete(gpu_delegate_);
    gpu_delegate_ = nullptr;
  }
#endif
  if (interpreter_ != nullptr) {
    TfLiteInterpreterDelete(interpreter_);
    interpreter_ = nullptr;
  }
  if (interpreter_options_ != nullptr) {
    TfLiteInterpreterOptionsDelete(interpreter_options_);
    interpreter_options_ = nullptr;
  }
  if (model_ != nullptr) {
    TfLiteModelDelete(model_);
    model_ = nullptr;
  }
}

std::unique_ptr<YoloEngine> YoloEngine::Create(const std::string& model_path,
                                               const EngineOptions& options) {
  TfLiteModel* model = TfLiteModelCreateFromFile(model_path.c_str());
  if (model == nullptr) {
    return nullptr;
  }
  TfLiteInterpreterOptions* interpreter_options = TfLiteInterpreterOptionsCreate();
  if (interpreter_options == nullptr) {
    TfLiteModelDelete(model);
    return nullptr;
  }
  TfLiteInterpreterOptionsSetNumThreads(interpreter_options, options.num_threads);

  TfLiteInterpreter* interpreter = TfLiteInterpreterCreate(model, interpreter_options);
  if (interpreter == nullptr) {
    TfLiteInterpreterOptionsDelete(interpreter_options);
    TfLiteModelDelete(model);
    return nullptr;
  }

  auto engine =
      std::unique_ptr<YoloEngine>(new YoloEngine(options, model, interpreter_options, interpreter));
  if (!engine->InitializeDelegates()) {
    return nullptr;
  }

  if (TfLiteInterpreterAllocateTensors(interpreter) != kTfLiteOk) {
    return nullptr;
  }

  return engine;
}

bool YoloEngine::InitializeDelegates() {
  if (!options_.use_gpu) {
    return true;
  }

#if defined(__ANDROID__)
  TfLiteGpuDelegateOptionsV2 gpu_options = TfLiteGpuDelegateOptionsV2Default();
  gpu_options.inference_preference = TFLITE_GPU_INFERENCE_PREFERENCE_FAST_SINGLE_ANSWER;
  gpu_options.is_precision_loss_allowed = options_.allow_fp16 ? 1 : 0;
  gpu_delegate_ = reinterpret_cast<TfLiteDelegate*>(TfLiteGpuDelegateV2Create(&gpu_options));
  if (gpu_delegate_ != nullptr) {
    TfLiteInterpreterOptionsAddDelegate(interpreter_options_, gpu_delegate_);
  }
#elif defined(__APPLE__) && TARGET_OS_IOS
  TfLiteGpuDelegateOptions gpu_options = TfLiteGpuDelegateOptionsDefault();
  gpu_options.allow_precision_loss = options_.allow_fp16 ? 1 : 0;
  gpu_options.wait_type = TFLGpuDelegateWaitType::TFLGpuDelegateWaitTypePassive;
  gpu_options.max_delegated_partitions = 1;
  gpu_delegate_ = reinterpret_cast<TfLiteDelegate*>(TfLiteGpuDelegateCreate(&gpu_options));
  if (gpu_delegate_ != nullptr) {
    TfLiteInterpreterOptionsAddDelegate(interpreter_options_, gpu_delegate_);
  }
#endif

  return true;
}

bool YoloEngine::ProcessFrame(const FrameMetadata& frame, std::vector<YoloDetection>* detections) {
  if (detections == nullptr) {
    return false;
  }
  std::vector<float> input_buffer;
  if (!PrepareInput(frame, &input_buffer)) {
    return false;
  }
  std::vector<float> output_tensor;
  std::vector<int> output_shape;
  if (!InvokeInterpreter(input_buffer, &output_tensor, &output_shape)) {
    return false;
  }
  auto decoded = yolo::DecodeDetections(output_tensor, output_shape, options_);
  *detections = std::move(decoded);
  return true;
}

bool YoloEngine::PrepareInput(const FrameMetadata& frame, std::vector<float>* input_buffer) {
  if (input_buffer == nullptr) {
    return false;
  }
  Yuv420ToRgb(frame, &rgb_buffer_);

  std::vector<uint8_t>* working_buffer = &rgb_buffer_;
  int processed_width = frame.width;
  int processed_height = frame.height;

  const int rotation = ((frame.rotation_degrees % 360) + 360) % 360;
  if (rotation != 0) {
    RotateRgb(rgb_buffer_, frame.width, frame.height, rotation, &rotated_buffer_);
    working_buffer = &rotated_buffer_;
    if (rotation == 90 || rotation == 270) {
      processed_width = frame.height;
      processed_height = frame.width;
    }
  } else {
    rotated_buffer_.clear();
  }

  ResizeAndNormalize(*working_buffer, processed_width, processed_height, options_.input_width,
                     options_.input_height, input_buffer);
  return true;
}

bool YoloEngine::InvokeInterpreter(const std::vector<float>& input_buffer,
                                   std::vector<float>* output_buffer,
                                   std::vector<int>* output_shape) {
  if (output_buffer == nullptr || output_shape == nullptr) {
    return false;
  }
  TfLiteTensor* input_tensor = TfLiteInterpreterGetInputTensor(interpreter_, 0);
  if (input_tensor == nullptr) {
    return false;
  }
  const size_t input_bytes = input_buffer.size() * sizeof(float);
  if (TfLiteTensorCopyFromBuffer(input_tensor, input_buffer.data(), input_bytes) != kTfLiteOk) {
    return false;
  }
  if (TfLiteInterpreterInvoke(interpreter_) != kTfLiteOk) {
    return false;
  }
  const TfLiteTensor* output_tensor = TfLiteInterpreterGetOutputTensor(interpreter_, 0);
  if (output_tensor == nullptr) {
    return false;
  }
  const int dims_count = TfLiteTensorNumDims(output_tensor);
  output_shape->resize(dims_count);
  for (int i = 0; i < dims_count; ++i) {
    (*output_shape)[i] = TfLiteTensorDim(output_tensor, i);
  }
  size_t output_size = 1;
  for (int dim : *output_shape) {
    output_size *= static_cast<size_t>(dim);
  }
  output_buffer->resize(output_size);
  if (TfLiteTensorCopyToBuffer(output_tensor, output_buffer->data(),
                               output_size * sizeof(float)) != kTfLiteOk) {
    return false;
  }
  return true;
}

}  // namespace yolo
