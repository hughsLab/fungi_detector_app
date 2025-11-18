cmake_minimum_required(VERSION 3.22.1)
project(yolo_engine_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT DEFINED TFLITE_HEADER_DIR)
  message(FATAL_ERROR "TFLITE_HEADER_DIR is not defined")
endif()

add_library(
  yolo_engine
  SHARED
  src/engine_api.cc
  src/image_utils.cc
  src/postprocess.cc
  src/yolo_engine.cc
)

target_include_directories(
  yolo_engine
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${TFLITE_HEADER_DIR}
)

target_compile_definitions(
  yolo_engine
  PRIVATE
    YOLO_ENGINE_BUILD
)

target_link_libraries(
  yolo_engine
  PRIVATE
    m
)

if(ANDROID)
  find_library(log-lib log)
  find_library(android-lib android)

  set(TFLITE_SO_DIR ${PROJECT_ROOT_DIR}/android/app/src/main/jniLibs/${ANDROID_ABI})
  set(TFLITE_JNI_SO ${TFLITE_SO_DIR}/libtensorflowlite_jni.so)
  if(NOT EXISTS ${TFLITE_JNI_SO})
    message(FATAL_ERROR "TensorFlow Lite JNI library not found at ${TFLITE_JNI_SO}")
  endif()
  add_library(tflite-lib SHARED IMPORTED)
  set_target_properties(tflite-lib PROPERTIES IMPORTED_LOCATION ${TFLITE_JNI_SO})

  target_link_libraries(
    yolo_engine
    PRIVATE
      ${log-lib}
      ${android-lib}
      tflite-lib
  )

  set(TFLITE_GPU_SO ${TFLITE_SO_DIR}/libtensorflowlite_gpu_jni.so)
  if(EXISTS ${TFLITE_GPU_SO})
    add_library(tflite-gpu-lib SHARED IMPORTED)
    set_target_properties(tflite-gpu-lib PROPERTIES IMPORTED_LOCATION ${TFLITE_GPU_SO})
    target_link_libraries(
      yolo_engine
      PRIVATE
        tflite-gpu-lib
    )
  endif()
endif()
