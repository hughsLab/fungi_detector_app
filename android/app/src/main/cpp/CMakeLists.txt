cmake_minimum_required(VERSION 3.22.1)

project(app_native LANGUAGES C CXX)

# The CMake source dir is <project>/android/app/src/main/cpp.
# Walk five levels up to reach the Flutter project root and normalize the path.
get_filename_component(PROJECT_ROOT_DIR "${CMAKE_SOURCE_DIR}/../../../../.." REALPATH)
set(TFLITE_HEADER_DIR ${PROJECT_ROOT_DIR}/third_party/tflite_flutter/src)

add_subdirectory(${PROJECT_ROOT_DIR}/native/yolo_engine ${CMAKE_BINARY_DIR}/native_yolo_engine)
