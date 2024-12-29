#ifndef USB_DESCRIPTORS_H_
#define USB_DESCRIPTORS_H_
#include "bsp/board_api.h"
#include "tusb.h"
#include "class/hid/hid_device.h"

#define HidPollingRate 5
enum
{
  ITF_NUM_KEYBOARD,
  ITF_NUM_MOUSE,
  ITF_NUM_ABSMOUSE,
  ITF_NUM_TOTAL
};

#endif