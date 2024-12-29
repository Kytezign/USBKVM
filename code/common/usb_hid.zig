const std = @import("std");
const hal = @import("pico_sdk");
const tusb = hal;

pub const MouseType = enum(u8) {
    RelMouse = 0,
    AbsMouse = 1,
};

pub fn initialize() void {
    hal.board_init();
    // init device stack on configured roothub port
    _ = hal.tud_init(hal.BOARD_TUD_RHPORT);
}

fn getTime_us() u64 {
    return hal.to_us_since_boot(hal.get_absolute_time());
}

/// Should be called as often as possible to keep the related buffers from filling up.
pub fn tasks() void {
    tusb.tud_task_ext(0xFFFF_FFFF, false);
    hid_task();
}

// We'll use global keboard modifires and keycodes that will be updated as fast as changes come in
// Trust that the host machine will never send keycode changes faster than 10ms so we don't miss anything
// Should be fine as long as we keep things in human time.  For a paste like features we'll just have to be careful
var kbrd_modifiers: u8 = 0;
pub var kbrd_keys: [6]u8 = .{ 0, 0, 0, 0, 0, 0 };
const null_array: [6]u8 = .{ 0, 0, 0, 0, 0, 0 };

pub fn updateKey(index: usize, value: u8) void {
    if (index < 6) {
        kbrd_keys[index] = value;
    } else if (index == 6) {
        kbrd_modifiers = value;
    }
    // Just ignore invalid index.  Should not hurt anybody.

}

pub fn updateKeys(modifiers: u8, keys: [6]u8) void {
    kbrd_modifiers = modifiers;
    kbrd_keys = keys;
}

// TODO: maybe we should accumulate x/y etc. until sent
// For Mouse we will attempt to implement a relitive movement mouse first. Since things like BIOS and early SW only support it
// And that's one of the primary use cases
// Absolute position will come next.  We'll play around with detection/switching when we get to it.
// we'll reuse the mouse fields for both.
var mouse_type: MouseType = MouseType.RelMouse;
var mouse_buttons: u8 = 0;
var mouse_x: i16 = 0;
var mouse_y: i16 = 0;
var mouse_vert: i8 = 0;
var mouse_hori: i8 = 0;
var mouse_update: bool = false;

pub fn updateMouse(m_type: MouseType, buttons: u8, vertical: i8, horizontal: i8) void {
    mouse_type = m_type;
    mouse_buttons = buttons;
    mouse_vert +|= vertical;
    mouse_hori +|= horizontal;
    mouse_update = true;
}

pub fn updateMousePos(x: i16, y: i16) void {
    switch (mouse_type) {
        .RelMouse => {
            mouse_x +%= x;
            mouse_y +%= y;
        },
        .AbsMouse => {
            mouse_x = x;
            mouse_y = y;
        },
    }
    mouse_update = true;
}

fn hid_task() void {
    const interval_ms = tusb.HidPollingRate;
    // TODO: understand these zig function level structs better.
    const stateinfo = struct {
        var next_time: u64 = 0;
        var kbrd_null_sent: bool = false;
    };
    // poll every 10ms
    // if it's not been 10ms return (do nothing)
    if (getTime_us() < stateinfo.next_time) {
        return;
    }
    stateinfo.next_time = interval_ms * 1000 + getTime_us();
    const keys_pressed = !std.mem.eql(u8, &kbrd_keys, &null_array) or kbrd_modifiers != 0;
    // Probably better way for zero compare.
    // We send a wakeup command if any keys are being pressed and it's suspended
    if (tusb.tud_suspended() and keys_pressed) {
        // Wake up host if we are in suspend mode
        // and REMOTE_WAKEUP feature is enabled by host
        _ = tusb.tud_remote_wakeup();
    } else {
        // keyboard interface
        if (tusb.tud_hid_n_ready(tusb.ITF_NUM_KEYBOARD) and (keys_pressed or !stateinfo.kbrd_null_sent)) {
            // only send one 0 keyboard message
            const report_id: u8 = 0;
            _ = tusb.tud_hid_n_keyboard_report(tusb.ITF_NUM_KEYBOARD, report_id, kbrd_modifiers, &kbrd_keys);
            if (!stateinfo.kbrd_null_sent and !keys_pressed) {
                stateinfo.kbrd_null_sent = true;
            } else {
                stateinfo.kbrd_null_sent = false;
            }
        }
        if (mouse_update) {
            switch (mouse_type) {
                .RelMouse => {
                    if (tusb.tud_hid_n_ready(tusb.ITF_NUM_MOUSE)) {
                        const report_id: u8 = 0;
                        const x: i8 = @truncate(mouse_x);
                        const y: i8 = @truncate(mouse_y);
                        _ = tusb.tud_hid_n_mouse_report(tusb.ITF_NUM_MOUSE, report_id, mouse_buttons, x, y, mouse_vert, mouse_hori);
                        mouse_x = 0;
                        mouse_y = 0;
                        mouse_hori = 0;
                        mouse_vert = 0;
                    }
                },
                .AbsMouse => {
                    if (tusb.tud_hid_n_ready(tusb.ITF_NUM_ABSMOUSE)) {
                        const report_id: u8 = 0;
                        _ = tusb.tud_hid_n_abs_mouse_report(tusb.ITF_NUM_ABSMOUSE, report_id, mouse_buttons, mouse_x, mouse_y, mouse_vert, mouse_hori);
                        mouse_hori = 0;
                        mouse_vert = 0;
                    }
                },
            }
        }
    }
}

pub var kbrd_protocol: u8 = 0;
pub var mouse_protocol: u8 = 0;
/// Invoked when received SET_PROTOCOL request
/// protocol is either HID_PROTOCOL_BOOT (0) or HID_PROTOCOL_REPORT (1)
/// For now it just sends update back to host
export fn tud_hid_set_protocol_cb(instance: u8, protocol: u8) void {
    if (instance == tusb.ITF_NUM_KEYBOARD) {
        kbrd_protocol = protocol;
    }
    if (instance == tusb.ITF_NUM_MOUSE) {
        mouse_protocol = protocol;
    }
}

// These were generated automatically with zig translate
// TODO: Clean up this stuff
pub export fn tud_hid_report_complete_cb(arg_instance: u8, arg_report: [*c]const u8, arg_len: u16) void {
    var instance = arg_instance;
    _ = &instance;
    var report = arg_report;
    _ = &report;
    var len = arg_len;
    _ = &len;
    _ = &instance;
    _ = &report;
    _ = &len;
}
pub export fn tud_hid_get_report_cb(arg_instance: u8, arg_report_id: u8, arg_report_type: tusb.hid_report_type_t, arg_buffer: [*c]u8, arg_reqlen: u16) u16 {
    var instance = arg_instance;
    _ = &instance;
    var report_id = arg_report_id;
    _ = &report_id;
    var report_type = arg_report_type;
    _ = &report_type;
    var buffer = arg_buffer;
    _ = &buffer;
    var reqlen = arg_reqlen;
    _ = &reqlen;
    _ = &instance;
    _ = &report_id;
    _ = &report_type;
    _ = &buffer;
    _ = &reqlen;
    return 0;
}
pub export fn tud_hid_set_report_cb(arg_instance: u8, arg_report_id: u8, arg_report_type: hal.hid_report_type_t, arg_buffer: [*c]const u8, arg_bufsize: u16) void {
    var instance = arg_instance;
    _ = &instance;
    var report_id = arg_report_id;
    _ = &report_id;
    var report_type = arg_report_type;
    _ = &report_type;
    var buffer = arg_buffer;
    _ = &buffer;
    var bufsize = arg_bufsize;
    _ = &bufsize;
    _ = &report_id;
    if (@as(c_int, @bitCast(@as(c_uint, instance))) == hal.ITF_NUM_KEYBOARD) {
        if (report_type == @as(c_uint, @bitCast(hal.HID_REPORT_TYPE_OUTPUT))) {
            if (@as(c_int, @bitCast(@as(c_uint, bufsize))) < @as(c_int, 1)) return;
            const kbd_leds: u8 = buffer[@as(c_uint, @intCast(@as(c_int, 0)))];
            _ = &kbd_leds;
        }
    }
}
