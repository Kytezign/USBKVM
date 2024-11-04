const std = @import("std");
const builtin = @import("builtin");
const ser = @import("serial.zig");

const sdlv = @cImport({
    @cInclude("sdl_video.c");
});

const sdl3 = @cImport({
    @cInclude("build/include/SDL3/SDL.h");
});
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
        // timeout when data is not avalible rather than stall
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
        // Send the reset command a few times just in case...
        self.sendCommand(0, 0, 0);
        self.sendCommand(0, 0, 0);
        self.sendCommand(0, 0, 0);
        self.sendCommand(0, 0, 0);
        self.sendCommand(0, 0, 0);

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
            std.debug.print("{s}", .{v});
        }
    }
    pub fn sendCommand(self: Self, cmd: u8, meta: u8, data: u16) void {
        const bytes: [4]u8 = .{ cmd, meta, @intCast((data >> 8) & 0xFF), @intCast(data & 0xFF) };
        self.port.writer().writeAll(&bytes) catch |err| {
            std.debug.print("Failed to write to serial port: {s}\n", .{@errorName(err)});
        };
    }
};

const KeyboardCtrl = struct {
    const Self = KeyboardCtrl;
    const KBRDCMD = 3; // TODO make this related to the enum in uCode?

    serialport: SerialPort,
    modifiers: u8 = 0, // placeholder for special modifier handling - not used currently.
    pressedkeys: [6]u8 = .{ 0, 0, 0, 0, 0, 0 },

    pub fn init(serial: SerialPort) Self {
        var self = KeyboardCtrl{ .serialport = serial };
        self.clearKeys();
        return self;
    }

    fn clearKeys(self: *Self) void {
        self.serialport.sendCommand(KBRDCMD, 0, 0); // Clear modifiers
        self.pressedkeys = .{ 0, 0, 0, 0, 0, 0 };
        for (0.., self.pressedkeys) |i, elem| {
            self.serialport.sendCommand(KBRDCMD, @truncate(2 + i), elem);
        }
    }

    fn sendKeyPress(self: *Self, key_code: u8) void {
        var empty_index: usize = 0xFF;
        // TODO: if key is modifier handle diffrently.  For now we just use one of the 6 slots for modifiers also which is probably good enough.
        for (0.., self.pressedkeys) |i, k| {
            if (k == key_code) {
                return; // key is already pressed.  Nothing to do here
            }
            if (k == 0 and empty_index == 0xFF) {
                empty_index = i;
            }
        }
        if (empty_index != 0xFF) {
            self.serialport.sendCommand(KBRDCMD, @truncate(2 + empty_index), key_code);
            self.pressedkeys[empty_index] = key_code;
        }
        // else - If there are no empty spots we just ignore the key press.
    }

    fn sendKeyRelease(self: *Self, key_code: u8) void {
        // TODO need to handle mod keys diffrently if we impement that.

        for (0.., self.pressedkeys) |i, k| {
            if (k == key_code) {
                self.pressedkeys[i] = 0;
                self.serialport.sendCommand(KBRDCMD, @truncate(i + 2), 0);
            }
        }
    }
};

// class ABSMOUSE:
//     def __init__(self, ctrl):
//         self._ctrl = ctrl

//     def send_mouse_move(self, x, y):
//         # print("mouse", x,y)
//         self._ctrl.send_command(CMDABSMOUSE,ABSX, x)
//         self._ctrl.send_command(CMDABSMOUSE,ABSY, y)

//     def send_mouse_buttons(self, buttons):
//         self._ctrl.send_command(CMDABSMOUSE, ABSBUTTON, buttons) # pass the mask through?

//     def send_mouse_wheel(self, x, y):
//         self._ctrl.send_command(CMDABSMOUSE, ABSWHEEL, (x <<8) | (y & 0xFF))

const AbsMouseCtrl = struct {
    const Self = AbsMouseCtrl;
    const CMDABSMOUSE = 4; // TODO make this related to the enum in uCode?

    const ABSX = 0;
    const ABSY = 1;
    const ABSBUTTON = 2;
    const ABSWHEEL = 3;

    serialport: SerialPort,

    pub fn init(serial: SerialPort) Self {
        const self = AbsMouseCtrl{ .serialport = serial };
        return self;
    }
    pub fn sendMouseMove(self: Self, x: u16, y: u16) void {
        self.serialport.sendCommand(CMDABSMOUSE, ABSX, x);
        self.serialport.sendCommand(CMDABSMOUSE, ABSY, y);
    }

    pub fn sendMouseButtons(self: Self, buttons: u16) void {
        self.serialport.sendCommand(CMDABSMOUSE, ABSBUTTON, buttons);
    }
    pub fn sendMouseWheel(self: Self, x: i8, y: i8) void {
        const ux: u16 = @as(u8, @bitCast(x));
        const uy: u16 = @as(u8, @bitCast(y));
        self.serialport.sendCommand(CMDABSMOUSE, ABSWHEEL, (ux << 8) | uy);
    }
};

pub fn main() !void {
    var iterator = try ser.list_info();
    defer iterator.deinit();
    var serialport_o: ?SerialPort = null;

    while (try iterator.next()) |info| {
        if (info.vid == 0xCAFE and info.pid == 0x4003) {
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
        std.debug.print("Failed to fined serial port\n", .{});
        return;
    }
    var serialport: SerialPort = serialport_o orelse unreachable;
    var kbdctrl: KeyboardCtrl = KeyboardCtrl.init(serialport);
    var absmouse: AbsMouseCtrl = AbsMouseCtrl.init(serialport);

    var appres: sdl3.SDL_AppResult = undefined;
    // Start video
    appres = sdlv.init();
    defer sdlv.deinit();

    // TODO: A better way to handle these events?
    //       Right now they are stored in a global variable in the c file
    //       which works but might be alittle obscure.  I can't figure out how to get them in this file then pass to pollEvent
    while (true) {
        sdlv.renderframe();
        try serialport.readAndLog();
        if (sdlv.pollEvent()) {
            switch (sdlv.event.type) {
                sdl3.SDL_EVENT_QUIT => {
                    break;
                },
                sdl3.SDL_EVENT_KEY_DOWN => {
                    kbdctrl.sendKeyPress(@truncate(sdlv.event.key.scancode));
                },
                sdl3.SDL_EVENT_KEY_UP => {
                    kbdctrl.sendKeyRelease(@truncate(sdlv.event.key.scancode));
                },
                sdl3.SDL_EVENT_MOUSE_MOTION => {
                    // Renderer is the same high/width as the camera image (see c code)
                    // Event is converted to render coodinates in c code.
                    if (sdlv.img_width > 0 and sdlv.img_height > 0) {
                        const x: u16 = @intFromFloat(sdlv.event.motion.x / @as(f32, @floatFromInt(sdlv.img_width)) * 32767);
                        const y: u16 = @intFromFloat(sdlv.event.motion.y / @as(f32, @floatFromInt(sdlv.img_height)) * 32767);
                        absmouse.sendMouseMove(x, y);
                    }
                },
                sdl3.SDL_EVENT_MOUSE_BUTTON_DOWN, sdl3.SDL_EVENT_MOUSE_BUTTON_UP => {
                    const btns = sdl3.SDL_GetMouseState(null, null);
                    // btns has the middle in betwen left and right but that's not what I want so...
                    const rawbtns: u16 = @truncate((btns & 0b111001) | (btns & 0b100) >> 1 | (btns & 0b10) << 1);
                    absmouse.sendMouseButtons(rawbtns);
                },
                sdl3.SDL_EVENT_MOUSE_WHEEL => {
                    const x: i8 = @intFromFloat(sdlv.event.wheel.x);
                    const y: i8 = @intFromFloat(sdlv.event.wheel.y);
                    absmouse.sendMouseWheel(x, y);
                },
                else => {},
            }
        }
    }
}
