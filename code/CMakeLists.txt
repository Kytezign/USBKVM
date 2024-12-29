set(PROJECT USBKVM)
cmake_minimum_required(VERSION 3.12)
# set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)
include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)
project(${PROJECT} C CXX ASM)

# add_compile_definitions()

pico_sdk_init()


add_subdirectory(µhost)
add_subdirectory(µguest)
