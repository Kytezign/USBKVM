set(PROJECT hid_forward)
cmake_minimum_required(VERSION 3.12)
include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)
project(${PROJECT} C CXX ASM)
set(DPICO_BOARD pico)
pico_sdk_init()
add_executable(${PROJECT} main.c)
# pico_set_binary_type(${PROJECT} no_flash)

pico_add_extra_outputs(${PROJECT})

set(PICO_PIO_USB_SRC $ENV{PIO_USB_PATH}/src)
pico_generate_pio_header(${PROJECT} ${PICO_PIO_USB_SRC}/usb_tx.pio)
pico_generate_pio_header(${PROJECT} ${PICO_PIO_USB_SRC}/usb_rx.pio)

target_sources(${PROJECT}  PUBLIC
        ${CMAKE_CURRENT_LIST_DIR}/main.c
        ${PICO_PIO_USB_SRC}/pio_usb.c
        ${PICO_PIO_USB_SRC}/pio_usb_device.c
        ${PICO_PIO_USB_SRC}/usb_crc.c
        ${CMAKE_CURRENT_LIST_DIR}/msc_disk.c
        ${CMAKE_CURRENT_LIST_DIR}/usb_descriptors.c

            )

target_include_directories(${PROJECT} PRIVATE

            # Standard
            ${CMAKE_CURRENT_LIST_DIR}
    
            # Pico PIO USB
            ${PICO_PIO_USB_SRC}

            ${PICO_SDK_PATH}
    )
target_link_libraries(${PROJECT} PUBLIC 
                                pico_stdlib 
                                pico_multicore 
                                hardware_pio
                                hardware_dma
                                tinyusb_device
                                tinyusb_board                        
                                )

                                    