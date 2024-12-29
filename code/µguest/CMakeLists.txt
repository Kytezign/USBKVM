set(PROJECT uguest)
cmake_minimum_required(VERSION 3.12)
include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)
project(${PROJECT} C CXX ASM)
pico_sdk_init()
add_executable(${PROJECT})
pico_generate_pio_header(${PROJECT}  ${CMAKE_SOURCE_DIR}/common/async_spi.pio)

target_sources(${PROJECT}  PUBLIC
                ${CMAKE_CURRENT_LIST_DIR}/usb_descriptors.c
            )



target_include_directories(${PROJECT} PUBLIC ${CMAKE_CURRENT_LIST_DIR} ${CMAKE_SOURCE_DIR}/common ${CMAKE_SOURCE_DIR}/build)
# Connect to zig output
add_library(zig_library STATIC IMPORTED)
set_property(TARGET zig_library PROPERTY   IMPORTED_LOCATION "${CMAKE_SOURCE_DIR}/zig-out/lib/libzguest.a")
target_link_libraries(${PROJECT} pico_stdlib hardware_pio zig_library tinyusb_device tinyusb_board)

pico_add_extra_outputs(${PROJECT})
