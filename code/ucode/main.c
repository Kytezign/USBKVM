#include <stdio.h>
#include "hardware/clocks.h"
#include <pico/stdlib.h>

#include "hardware/gpio.h"
#include "pico/multicore.h"
#include "pico/bootrom.h"
#include "pico/time.h"
#include "pio_usb.h"
#include "bsp/board.h"
#include "tusb.h"




#include "device/usbd.h"
#include "class/hid/hid_device.h"
#include "abs_mouse.c"


typedef unsigned int uint;


#define mprintf(...)  char _tmp_buff[128]; \
                      int _tmp_count = sprintf (_tmp_buff, __VA_ARGS__); \
                      tud_cdc_write(_tmp_buff, _tmp_count);\
                      tud_cdc_write_flush();


/// HW PIN Definitions
#define PIN_USB_PIO_DP 3
#define USB_PIO_PINOUT PIO_USB_PINOUT_DMDP
#define PIN_GUEST_VBUS 1
#define PIN_PULLUP_EN 11 // TODO: Setting this to 4,5  just breaks things (locks up USB/fails to enumerate) and I don't know why...


#define DEBOUNCE_TIME_MS 0
#define KB_WAIT_MS 10

/// Globals
static usb_device_t *usb_device = NULL;
bool pull_up_flag = 0;
uint32_t pull_up_debounce_timeout;

uint8_t keyboard_report[8] = {0};
uint32_t kbrd_timeout=0;

static abs_mouse_report_t abs_mouse_report = {0};


/*___________________________________________________________________-
***********************************************************************8
________________________________________________________________________---*/
enum cmd_types {
  CMDNOP=0,
  CMDDEBUG,
  CMDRESV,
  CMDKBRD,
  CMDABSMOUSE,
  CMDUSBBOOT
}; 


enum mouse_ctrl {
  ABSX,
  ABSY,
  ABSBUTTON,
  ABSWHEEL
};

struct cmd_t
{
    uint8_t command;
    uint8_t meta;
    uint16_t data;
};


struct cmd_t read_in_command(){
    // Command must be 32 bytes long. 
    // first char recived is the command
    // A 0x00 command will reset the interface - cut short the read. The sender can do a 0x0000_0000 to reset
    // down stream command interpreters need to handle the 0x00 condition for all bytes just in case there is an out of sync condition.
    struct cmd_t new_cmd = {0,0,0};
    if (tud_cdc_available()){
      int d_int = tud_cdc_read_char();
      if (d_int == -1 | d_int == 0){
          return new_cmd;
      }
      new_cmd.command = d_int;
      new_cmd.meta = tud_cdc_read_char();
      new_cmd.data = tud_cdc_read_char() << 8;
      new_cmd.data |= tud_cdc_read_char();
    }
    return new_cmd;

}

void reset_ic(const struct cmd_t cmd ){
  mprintf("Reseting into USB BOOT.  Good bye.\n");
  sleep_ms(300);
  rom_reset_usb_boot(0,0);
}

/// @brief Send keyboard report
/// @param cmd cmd consists of meta = index and data equals the keystroke. 
void send_keystroke(const struct cmd_t cmd){
  if (usb_device != NULL && gpio_get(PIN_PULLUP_EN)) {
    while (to_ms_since_boot(get_absolute_time())<kbrd_timeout);
    keyboard_report[cmd.meta] = cmd.data & 0xFF;
    // mprintf("KeyPosSet %d %d,  %d\n", cmd.meta, cmd.data, to_ms_since_boot(get_absolute_time()));
    // mprintf("kyboard\n");
    endpoint_t *ep = pio_usb_get_endpoint(usb_device, 1);
    pio_usb_set_out_data(ep, keyboard_report, sizeof(keyboard_report));
    kbrd_timeout = to_ms_since_boot(get_absolute_time()) + KB_WAIT_MS;
  }
}

void update_abs_mouse(const struct cmd_t cmd){
    if (usb_device != NULL && gpio_get(PIN_PULLUP_EN)) {
      abs_mouse_report.wheel = 0;
      abs_mouse_report.pan = 0; // Only send wheel/pan when events actually happen
      switch (cmd.meta)
      {
      case ABSX:
        abs_mouse_report.x = cmd.data;
        break;
      case ABSY:
        abs_mouse_report.y = cmd.data;
        break;
      case ABSBUTTON:
        abs_mouse_report.buttons = cmd.data & 0xFF;
        // mprintf("ABS mouse btn test %d\n", cmd.data);
      case ABSWHEEL:
        abs_mouse_report.wheel = cmd.data & 0xFF;
        abs_mouse_report.pan = cmd.data >> 8;

      default:
        break;
      }
      endpoint_t *ep = pio_usb_get_endpoint(usb_device, 2);
      pio_usb_set_out_data(ep, (uint8_t *)&abs_mouse_report, sizeof(abs_mouse_report));
  }
}


void execute_command(struct cmd_t cmd){
    // mprintf("DEBUG:Command Received (0x%02x  0x%02x  0x%04x)\n",cmd.command, cmd.meta, cmd.data);
    switch(cmd.command)
    {
        case CMDNOP: break;
        case CMDKBRD: send_keystroke(cmd);
                      break;
        case CMDABSMOUSE: update_abs_mouse(cmd);
                          break;
        case CMDUSBBOOT: reset_ic(cmd);
                          break;
        default: mprintf("ERROR:Unkown Command Received (0x%02x  0x%02x  0x%04x)\n",cmd.command, cmd.meta, cmd.data);
    }

}




/*____________________________________________________________________--
_______________________________________________________________________\
_______________________________________________________________________*/



void guest_vbus_callback(uint gpio, uint32_t events) {
    // Put the GPIO event(s) that just happened into event_str
    // so we can print it
    if (gpio == PIN_GUEST_VBUS){
      mprintf("Guest VBUS %d\n", events >> 3);
      pull_up_flag = events >> 3;
      pull_up_debounce_timeout = to_ms_since_boot(get_absolute_time()) + DEBOUNCE_TIME_MS;
    }
}



tusb_desc_device_t const pio_desc_device = {.bLength = sizeof(tusb_desc_device_t),
                                        .bDescriptorType = TUSB_DESC_DEVICE,
                                        .bcdUSB = 0x0110,
                                        .bDeviceClass = 0x00,
                                        .bDeviceSubClass = 0x00,
                                        .bDeviceProtocol = 0x00,
                                        .bMaxPacketSize0 = 64,

                                        .idVendor = 0xCafe,
                                        .idProduct = 0,
                                        .bcdDevice = 0x0100,

                                        .iManufacturer = 0x01,
                                        .iProduct = 0x02,
                                        .iSerialNumber = 0x03,

                                        .bNumConfigurations = 0x01};

enum {
  ITF_NUM_KEYBOARD,
  ITF_NUM_MOUSE,
  ITF_NUM_TOTAL,
};

enum {
  EPNUM_KEYBOARD = 0x81,
  EPNUM_MOUSE = 0x82,
};


uint8_t const desc_hid_keyboard_report[] =
{
  TUD_HID_REPORT_DESC_KEYBOARD()
};

uint8_t const desc_hid_mouse_report[] =
{
  //TUD_HID_REPORT_DESC_MOUSE()
  TUD_HID_REPORT_DESC_ABSMOUSE()
};

const uint8_t *report_desc[] = {desc_hid_keyboard_report,
                                desc_hid_mouse_report};

#define CONFIG_TOTAL_LEN  (TUD_CONFIG_DESC_LEN + 2*TUD_HID_DESC_LEN)
uint8_t const desc_configuration[] = {
    TUD_CONFIG_DESCRIPTOR(1, ITF_NUM_TOTAL, 0, CONFIG_TOTAL_LEN,
                          TUSB_DESC_CONFIG_ATT_REMOTE_WAKEUP, 100),
    TUD_HID_DESCRIPTOR(ITF_NUM_KEYBOARD, 0, HID_ITF_PROTOCOL_KEYBOARD,
                       sizeof(desc_hid_keyboard_report), EPNUM_KEYBOARD,
                       CFG_TUD_HID_EP_BUFSIZE, 10),
    TUD_HID_DESCRIPTOR(ITF_NUM_MOUSE, 0, HID_ITF_PROTOCOL_MOUSE,
                       sizeof(desc_hid_mouse_report), EPNUM_MOUSE,
                       CFG_TUD_HID_EP_BUFSIZE, 10),
};

static_assert(sizeof(pio_desc_device) == 18, "device desc size error");

const char *string_descriptors_base[] = {
    [0] = (const char[]){0x09, 0x04},
    [1] = "KVM HID",
    [2] = "KVM HID device",
    [3] = "123456",
};
static string_descriptor_t str_desc[4];

static void init_string_desc(void) {
  for (int idx = 0; idx < 4; idx++) {
    uint8_t len = 0;
    uint16_t *wchar_str = (uint16_t *)&str_desc[idx];
    if (idx == 0) {
      wchar_str[1] = string_descriptors_base[0][0] |
                     ((uint16_t)string_descriptors_base[0][1] << 8);
      len = 1;
    } else if (idx <= 3) {
      len = strnlen(string_descriptors_base[idx], 31);
      for (int i = 0; i < len; i++) {
        wchar_str[i + 1] = string_descriptors_base[idx][i];
      }

    } else {
      len = 0;
    }

    wchar_str[0] = (TUSB_DESC_STRING << 8) | (2 * len + 2);
  }
}

static usb_descriptor_buffers_t desc = {
    .device = (uint8_t *)&pio_desc_device,
    .config = desc_configuration,
    .hid_report = report_desc,
    .string = str_desc
};


void core1_main() {
    sleep_ms(10);

    pio_usb_configuration_t config = PIO_USB_DEFAULT_CONFIG;
    config.pin_dp = PIN_USB_PIO_DP;
    config.pinout = USB_PIO_PINOUT;
    init_string_desc();
    usb_device = pio_usb_device_init(&config, &desc);

  while (true) {
    pio_usb_device_task();
  }
}

/*****************MAIN************************/

int main() {
    struct cmd_t cmd;
    set_sys_clock_khz(120000, true);
    board_init(); 

    gpio_init(PIN_PULLUP_EN);
    gpio_init(PIN_GUEST_VBUS);
    gpio_set_dir(PIN_PULLUP_EN, GPIO_OUT);
    gpio_set_dir(PIN_GUEST_VBUS, GPIO_IN);
    gpio_put(PIN_PULLUP_EN, 0); 

    // init device stack on configured roothub port
    tud_init(BOARD_TUD_RHPORT);
    sleep_ms(10);
    multicore_reset_core1();
    // all USB task run in core1
    multicore_launch_core1(core1_main);
    sleep_ms(100);

    pull_up_flag = gpio_get(PIN_GUEST_VBUS);
    gpio_set_irq_enabled_with_callback(PIN_GUEST_VBUS, GPIO_IRQ_EDGE_FALL|GPIO_IRQ_EDGE_RISE , true, &guest_vbus_callback);


    while (true) {
        tud_task(); // tinyusb device task

        cmd = read_in_command();
        execute_command(cmd);
        bool tmp = gpio_get(PIN_GUEST_VBUS);
        if (pull_up_flag != tmp){
          pull_up_flag = tmp;
        }
        if (pull_up_flag != gpio_get(PIN_PULLUP_EN) &&  to_ms_since_boot(get_absolute_time()) > pull_up_debounce_timeout){
          mprintf("Updating pull up now from %d to %d\n", gpio_get(PIN_PULLUP_EN), pull_up_flag);
          gpio_put(PIN_PULLUP_EN, pull_up_flag);
          sleep_ms(100); // Enumeration time? TODO: fix this, I'm not yet sure how to watch for enumeration/disconnection etc.
        }
    }
}

// Invoked when cdc when line state changed e.g connected/disconnected
void tud_cdc_line_state_cb(uint8_t itf, bool dtr, bool rts)
{
  (void) itf;
  (void) rts;

  // TODO set some indicator
  if ( dtr )
  {
    // Terminal connected
  }else
  {
    // Terminal disconnected
  }
}
