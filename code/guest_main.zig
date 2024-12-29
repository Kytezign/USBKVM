const std = @import("std");
const hid = @import("common/usb_hid.zig");
const spi = @import("common/pio_spi.zig");
const commands = @import("common/commands.zig");
const hal = @import("pico_sdk");
const pins = @import("µguest/pins.zig");

var to_host_spi: spi.PioAsyncSpiController = undefined;
var from_host_spi: spi.PioAsyncSpiPeripheral = undefined;

fn get_us_time() u64 {
    return hal.to_us_since_boot(hal.get_absolute_time());
}

fn writeMsg(msg: []u8) void {
    for (msg) |c| {
        to_host_spi.send_cmd(.{ .cmd = .Msg, .data = c });
    }
    to_host_spi.send_cmd(.{ .cmd = .Msg, .data = 0 });
}

fn sendStringToHost(comptime fmt: []const u8, args: anytype) void {
    // const count: usize = @intCast(std.fmt.count(fmt, args));
    var write_buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&write_buf, fmt, args) catch unreachable;
    writeMsg(msg);
}

/// This will cause watchdog reset but the message to host should get out first.
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    hal.watchdog_disable();
    sendStringToHost("{s}", .{msg});
    hal.watchdog_enable(1, true);
    while (true) {}
}

fn restartToBootLoader() void {
    hal.watchdog_disable();
    sendStringToHost("Resetting To USB Bootloader", .{});
    hal.sleep_ms(500); // time to flush
    hal.rom_reset_usb_boot(0, 0);
}

fn restart() void {
    // let watchdog take it from here
    sendStringToHost("Resetting Guest", .{});
    hal.sleep_ms(500); // time to flush
    hal.watchdog_enable(1, true); // watchdog with enough time (hopefully to send messages in the case of a zig panic)
}

fn cmdEcho(cmd: commands.CmdPk) void {
    to_host_spi.send_cmd(cmd);
}

fn doMouseUpdate(data: u32) void {
    const abs_mouse: hid.MouseType = @enumFromInt(@as(u8, @truncate(data & 0xFF)));
    const buttons: u8 = @truncate((data >> 8) & 0xFF);
    const vert: i8 = @intCast(@as(i8, @bitCast(@as(u8, @truncate((data >> 16) & 0xFF)))));
    const hori: i8 = @intCast(@as(i8, @bitCast(@as(u8, @truncate((data >> 24) & 0xFF)))));
    hid.updateMouse(abs_mouse, buttons, vert, hori);
}

fn doMousePosUpdate(data: u32) void {
    const x: i16 = @bitCast(@as(u16, @truncate((data) & 0xFFFF)));
    const y: i16 = @bitCast(@as(u16, @truncate((data >> 16) & 0xFFFF)));
    // sendStringToHost("Mouse update x:{d}, y:{d}", .{ x, y });
    hid.updateMousePos(x, y);
}

fn handleCmd() void {
    const acmd = from_host_spi.readCmd() catch null;
    if (acmd) |cmd| {
        switch (cmd.cmd) {
            .RestartToBootloader => restartToBootLoader(),
            .Echo4 => cmdEcho(cmd),
            .Echo16 => cmdEcho(cmd),
            .Echo32 => cmdEcho(cmd),
            .DoPanic => restart(),
            // TODO: some debug around key updates
            .KeyBoardUpdate => {
                hid.updateKey(cmd.data >> 8, @truncate(cmd.data & 0xFF));
                // sendStringToHost("Kbrd RX {any}", .{hid.kbrd_keys});
            },
            .MouseUpdate => doMouseUpdate(cmd.data),
            .ResetBus => {},
            .MousePosUpdate => doMousePosUpdate(cmd.data),
            .Msg => {},
            _ => {
                sendStringToHost("Invalid Command: 0x{X}: 0x{X}", .{ cmd.cmd, cmd.data });
            },
        }
    }
}

export fn main() void {
    hid.initialize();
    to_host_spi = spi.PioAsyncSpiController.init(pins.G2HSPI_D0, 1, pins.G2HSPI_CLK, pins.G2HSPI_READY, 8) catch {
        return;
    };
    to_host_spi.write(0);
    to_host_spi.write(0);
    to_host_spi.write(0);
    from_host_spi = spi.PioAsyncSpiPeripheral.init(pins.H2GSPI_D0, pins.H2GSPI_COUNT, pins.H2GSPI_READY, 8) catch {
        return;
    };
    hal.watchdog_enable(100, true);
    var next_time: u64 = 0;
    while (true) {
        hal.watchdog_update();
        if (get_us_time() > next_time) {
            // sendStringToHost("Still ALIVE!", .{});
            next_time = get_us_time() + 5_000_000;
        }
        handleCmd();
        hid.tasks();
    }
}
