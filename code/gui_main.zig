const std = @import("std");
const video = @import("guihost/sdl_capture.zig");
const s = @cImport({
    @cInclude("SDL3/SDL.h");
});
const cString = @cImport({
    @cInclude("string.h");
});
// TODO Standardized HID polling.  It's used in 2 places currently: In main loop for mouse updates and in the sendText function

const builtin = @import("builtin");
const ser = @import("guihost/serial.zig");
const commands = @import("common/commands.zig");
const Cmds = @import("common/commands.zig").Cmds;

const VTIME = 5;
const VMIN = 6;

const SerialPort = struct {
    const Self = SerialPort;

    port: std.fs.File,

    pub fn init(port_name: []const u8) !Self {
        var self: Self = undefined;
        self.port = std.fs.cwd().openFile(port_name, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("Invalid config: the serial port '{s}' does not exist.\n", .{port_name});
                return err;
            },
            else => return err,
        };

        try ser.configureSerialPort(self.port, ser.SerialConfig{
            .baud_rate = 115200,
            .word_size = .eight,
            .parity = .none,
            .stop_bits = .one,
            .handshake = .none,
        });
        // timeout when data is not available rather than stall
        // https://www.reddit.com/r/Zig/comments/1fjt883/setting_timeout_on_readbyte/
        switch (builtin.os.tag) {
            // .windows => {
            //     // TODO see https://www.reddit.com/r/Zig/comments/1fjt883/setting_timeout_on_readbyte/
            // },
            .linux, .macos => {
                var settings = try std.posix.tcgetattr(self.port.handle);
                settings.cc[VMIN] = 0;
                settings.cc[VTIME] = 0;
                try std.posix.tcsetattr(self.port.handle, .NOW, settings);
            },
            else => @compileError("unsupported OS, please implement!"),
        }
        self.sendCmdReset();

        return self;
    }
    pub fn deinit(self: Self) void {
        self.port.close();
        self.* = undefined;
    }

    /// Read out the buffer and write to std out/std err?
    pub fn readAndLog(self: Self) !void {
        var buf: [1024]u8 = undefined;
        const count = try self.port.reader().read(&buf);
        if (count > 0) {
            const v = buf[0..count];
            std.debug.print("\x1b[94m{s}\x1b[0m", .{v});
        }
    }
    fn sendCmdReset(self: Self) void {
        const buff: [4]u8 = .{ 0, 0, 0, 0 };
        self.port.writer().writeAll(&buff) catch |err| {
            std.debug.print("Failed to write to serial port: {s}\n", .{@errorName(err)});
        };
    }
    pub fn sendCommand(self: Self, cmd: Cmds, data: u32) void {
        var buff: [5]u8 = undefined;
        const buff_out = commands.packCommand(&buff, cmd, data);
        self.port.writer().writeAll(buff_out) catch |err| {
            std.debug.print("Failed to write to serial port: {s}\n", .{@errorName(err)});
        };
    }
};

const KeyboardCtrl = struct {
    const Self = KeyboardCtrl;

    serialport: SerialPort,
    modifiers: u8 = 0, // placeholder for special modifier handling - not used currently.
    pressedkeys: [6]u8 = .{ 0, 0, 0, 0, 0, 0 },

    pub fn init(serial: SerialPort) Self {
        var self = KeyboardCtrl{ .serialport = serial };
        self.clearKeys();
        return self;
    }

    fn updateKeys(self: *Self, index: usize, key_code: u8) void {
        std.debug.assert(index < 7);
        const indx: u16 = @truncate(index);
        const d = indx << 8 | key_code;
        self.serialport.sendCommand(Cmds.KeyBoardUpdate, d);
    }

    fn clearKeys(self: *Self) void {
        self.updateKeys(6, 0);
        self.pressedkeys = .{ 0, 0, 0, 0, 0, 0 };
        for (0.., self.pressedkeys) |i, elem| {
            self.updateKeys(i, elem);
        }
    }
    fn checkIsPressed(self: *Self, key_code: u8) bool {
        for (self.pressedkeys) |scode| {
            if (key_code == scode) {
                return true;
            }
        }
        return false;
    }

    fn sendKeyPress(self: *Self, key_code: u8) void {
        var empty_index: usize = 0xFF;
        // TODO: if key is modifier handle differently.  For now we just use one of the 6 slots for modifiers also which is probably good enough.
        for (0.., self.pressedkeys) |i, k| {
            if (k == key_code) {
                return; // key is already pressed.  Nothing to do here
            }
            if (k == 0 and empty_index == 0xFF) {
                empty_index = i;
            }
        }
        if (empty_index != 0xFF) {
            self.updateKeys(empty_index, key_code);
            self.pressedkeys[empty_index] = key_code;
        }
        // std.debug.print("Keys: {any}\n", .{self.pressedkeys});
        // else - If there are no empty spots we just ignore the key press.
    }

    fn sendKeyRelease(self: *Self, key_code: u8) void {
        // TODO need to handle mod keys differently if we implement that.
        for (0.., self.pressedkeys) |i, k| {
            if (k == key_code) {
                self.pressedkeys[i] = 0;
                self.updateKeys(i, 0);
            }
        }
    }
    /// Sends input text as keystrokes.  For invalid stuff it just ignores it
    /// Based on host keyboard layout plus a few workarounds that might not make sense generally (see get scan code).
    fn sendText(self: *Self, text: []const u8) void {
        // Press as many keys as we can until we fill up the buffer 5 keys (one spot for shift... for now)
        // or shifted for one key is different than others. or a key must be re-pressed
        // when one of those conditions is true clear keys and continue with the new character
        // Normally we trust human typing will be slower than 10ms (polling rate)
        var shift_pressed: bool = false;
        var keycount: u32 = 0;
        for (text) |char| {
            const shift = std.ascii.isUpper(char) or isShifted(char);
            const char_lower = std.ascii.toLower(char);
            const scode = getScanCode(char_lower);
            // This is to save time.  Clearing one or more keys at the same time doesn't matter.
            if (shift != shift_pressed or keycount == 5 or self.checkIsPressed(scode)) {
                std.time.sleep(5_000_000); // 5ms
                self.clearKeys();
                std.time.sleep(5_000_000); // 5ms
                keycount = 0;
            }
            keycount += 1;

            shift_pressed = shift;
            // std.debug.print("text: {c} 0x{x} 0x{X}, 0x{X}\n", .{ char, char, scode, char_lower });
            if (shift) {
                // does not send anything if shift is already pressed.
                self.sendKeyPress(@truncate(@as(u32, @intCast(s.SDL_SCANCODE_LSHIFT))));
            }
            self.sendKeyPress(scode);
            // Bit of a hack here to keep the frame updating during this...
            video.renderNextFrame();
        }
        std.time.sleep(5_000_000); // 10ms
        self.clearKeys();
    }
    // const shifted = [_]u8{'!', '@', '#', "$"};
    const shifted = "!@#$%^&*()_+{}:<>?|~\"";
    fn isShifted(c: u8) bool {
        return for (shifted) |other| {
            if (c == other) {
                break true;
            }
        } else false;
    }
    /// Handles typed characters using SDL ScancodeFromKey plus a few others
    fn getScanCode(char: u8) u8 {
        const scode: u8 = switch (char) {
            '\n' => 0x28,
            '\\', '|' => 0x31,
            '(' => 0x26,
            ')' => 0x27,
            else => @truncate(s.SDL_GetScancodeFromKey(char, null)),
        };
        return scode;
    }
};

const RelMouseCtrl = struct {
    serialport: SerialPort,

    pub fn init(serial: SerialPort) RelMouseCtrl {
        const self = RelMouseCtrl{ .serialport = serial };
        return self;
    }

    pub fn sendMouseMove(self: RelMouseCtrl, x: i8, y: i8) void {
        const tmp: u32 = @as(u8, @bitCast(y));
        self.serialport.sendCommand(Cmds.MousePosUpdate, (tmp << 16) | @as(u8, @bitCast(x)));
    }

    pub fn sendMouseUpdate(self: RelMouseCtrl, buttons: u8, vert: i8, hori: i8) void {
        const raw_vert: u32 = @as(u8, @bitCast(vert));
        const raw_hori: u32 = @as(u8, @bitCast(hori));
        self.serialport.sendCommand(Cmds.MouseUpdate, @as(u32, buttons) << 8 | raw_vert << 16 | raw_hori << 24);
    }
};

// const AbsMouseCtrl = struct {
//     const Self = AbsMouseCtrl;
//     const CMDABSMOUSE = 4; // TODO make this related to the enum in uCode?

//     const ABSX = 0;
//     const ABSY = 1;
//     const ABSBUTTON = 2;
//     const ABSWHEEL = 3;

//     serialport: SerialPort,

//     pub fn init(serial: SerialPort) Self {
//         const self = AbsMouseCtrl{ .serialport = serial };
//         return self;
//     }
//     pub fn sendMouseMove(self: Self, x: u16, y: u16) void {
//         self.serialport.sendCommand(CMDABSMOUSE, ABSX, x);
//         self.serialport.sendCommand(CMDABSMOUSE, ABSY, y);
//     }

//     pub fn sendMouseButtons(self: Self, buttons: u16) void {
//         self.serialport.sendCommand(CMDABSMOUSE, ABSBUTTON, buttons);
//     }
//     pub fn sendMouseWheel(self: Self, x: i8, y: i8) void {
//         const ux: u16 = @as(u8, @bitCast(x));
//         const uy: u16 = @as(u8, @bitCast(y));
//         self.serialport.sendCommand(CMDABSMOUSE, ABSWHEEL, (ux << 8) | uy);
//     }
// };
const UnhandledError = error{
    SerialPortNotAvailable,
};

// these come from the uhost/usb_descriptors.c
const USBHOST_VID = 0x5730;
const USBHOST_PID = 0x4003;

pub fn main() !void {
    // Init
    var iterator = try ser.list_info();
    defer iterator.deinit();
    var serialport_o: ?SerialPort = null;

    while (try iterator.next()) |info| {
        if (info.vid == USBHOST_VID and info.pid == USBHOST_PID) {
            std.debug.print("\nPort name: {s}\n", .{info.port_name});
            std.debug.print(" - System location: {s}\n", .{info.system_location});
            std.debug.print(" - Friendly name: {s}\n", .{info.friendly_name});
            std.debug.print(" - Description: {s}\n", .{info.description});
            std.debug.print(" - Manufacturer: {s}\n", .{info.manufacturer});
            std.debug.print(" - Serial #: {s}\n", .{info.serial_number});
            std.debug.print(" - HW ID: {s}\n", .{info.hw_id});
            std.debug.print(" - VID: 0x{X:0>4} PID: 0x{X:0>4}\n", .{ info.vid, info.pid });
            serialport_o = try SerialPort.init(info.system_location);
            break; // doesn't handle multiple devices...
        }
    }
    if (serialport_o == null) {
        std.debug.print("Failed to find serial port\n", .{});
        return UnhandledError.SerialPortNotAvailable;
    }
    const serialport: SerialPort = serialport_o orelse unreachable;
    var kbdctrl: KeyboardCtrl = KeyboardCtrl.init(serialport);
    // var absmouse: AbsMouseCtrl = AbsMouseCtrl.init(serialport);
    var relmouse: RelMouseCtrl = RelMouseCtrl.init(serialport);
    _ = video.init();
    var mouse_time: i64 = std.time.milliTimestamp();

    while (true) {
        video.renderNextFrame();
        try serialport.readAndLog();
        // check mouse updates every 10ms
        if (std.time.milliTimestamp() > mouse_time) {
            var x: f32 = 0;
            var y: f32 = 0;
            _ = s.SDL_GetRelativeMouseState(&x, &y);
            // todo handle abs mouse sep if I ever get that working
            // std.debug.print("Motion x: {?}\n", .{event.motion.xrel});
            const x_int: i8 = @truncate(@as(i32, @intFromFloat(x)));
            const y_int: i8 = @truncate(@as(i32, @intFromFloat(y)));
            if (x_int != 0 or y_int != 0) {
                relmouse.sendMouseMove(x_int, y_int);
            }
            mouse_time += 5;
        }

        var event: s.SDL_Event = undefined;
        while (s.SDL_PollEvent(&event)) {
            switch (event.type) {
                s.SDL_EVENT_QUIT => {
                    return;
                },
                s.SDL_EVENT_KEY_DOWN => {
                    if (event.key.scancode == s.SDL_SCANCODE_INSERT) {
                        kbdctrl.clearKeys();
                        const c_clipboard = s.SDL_GetClipboardText();
                        const t = c_clipboard[0..cString.strlen(c_clipboard)];
                        kbdctrl.sendText(t);
                        s.SDL_free(c_clipboard);
                    } else {
                        // std.debug.print("Keydown: 0x{x}\n", .{event.key.scancode});
                        kbdctrl.sendKeyPress(@truncate(event.key.scancode));
                    }
                },
                s.SDL_EVENT_KEY_UP => {
                    kbdctrl.sendKeyRelease(@truncate(event.key.scancode));
                },
                s.SDL_EVENT_MOUSE_BUTTON_DOWN, s.SDL_EVENT_MOUSE_BUTTON_UP => {
                    const btns = s.SDL_GetMouseState(null, null);
                    // btns has the middle in between left and right but that's not what I want so...
                    const rawbtns: u8 = @truncate((btns & 0b111001) | (btns & 0b100) >> 1 | (btns & 0b10) << 1);
                    relmouse.sendMouseUpdate(rawbtns, 0, 0);
                },
                s.SDL_EVENT_MOUSE_WHEEL => {
                    const btns = s.SDL_GetMouseState(null, null);
                    // btns has the middle in betwen left and right but that's not what I want so...
                    const rawbtns: u8 = @truncate((btns & 0b111001) | (btns & 0b100) >> 1 | (btns & 0b10) << 1);
                    const x: i8 = @intFromFloat(event.wheel.x);
                    const y: i8 = @intFromFloat(event.wheel.y);
                    relmouse.sendMouseUpdate(rawbtns, x, y);
                },

                else => {},
            }
        }
    }
}
