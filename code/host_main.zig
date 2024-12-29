const std = @import("std");
const usb = @import("common/usb_serial.zig");
const hal = @import("pico_sdk");
const commands = @import("common/commands.zig");
const spi = @import("common/pio_spi.zig");
const pins = @import("µhost/pins.zig");

// -------------------------------------------

fn cmdEcho(data: u32) void {
    usb.print("Echo: 0x{X}", .{data});
}

fn restartToBootLoader(cmd_data: u32) void {
    if (cmd_data == 0xAAAA_AAAA) {
        hal.watchdog_disable();
        usb.print("Reseting into USB BOOT.  Good bye.", .{});
        hal.sleep_ms(500); // time to flush
        hal.rom_reset_usb_boot(0, 0);
    } else if (cmd_data == 0x5555_5555) {
        to_guest_spi.send_cmd(.{ .cmd = commands.Cmds.RestartToBootloader, .data = cmd_data });
    }
}

fn handleUSBCmd() void {
    const acmd = usb.readNextCmd() catch null;
    if (acmd) |cmd| {
        switch (cmd.cmd) {
            .RestartToBootloader => restartToBootLoader(cmd.data),
            .Echo4 => cmdEcho(cmd.data),
            .Echo16 => cmdEcho(cmd.data),
            .Echo32 => cmdEcho(cmd.data),
            .DoPanic => @panic("Test Panic"),
            .KeyBoardUpdate, .MouseUpdate, .MousePosUpdate => forwardToGuest(cmd),
            .ResetBus, .Msg => usb.print("Unused comand sent: 0x{X}: 0x{X}", .{ cmd.cmd, cmd.data }),
            _ => usb.print("Unused comand sent: 0x{X}: 0x{X}", .{ cmd.cmd, cmd.data }),
        }
    }
}

fn forwardToGuest(cmd: commands.CmdPk) void {
    to_guest_spi.send_cmd(cmd);
}

// TODO: could increase the size of data for more efficent use of the bus.
// TODO: These should maybe be static variables in the function?
var guest_msg_buffer: [256]u8 = undefined;
var buf_count: usize = 0;
/// handles guest message
fn guestMsg(data: u8) void {
    if (buf_count < guest_msg_buffer.len and data != 0) {
        guest_msg_buffer[buf_count] = data;
        buf_count += 1;
    } else {
        usb.print("Guest: {s}", .{guest_msg_buffer[0..buf_count]});
        buf_count = 0;
    }
}

fn handleGuestCmd() void {
    const acmd = from_guest_spi.readCmd() catch null;
    if (acmd) |cmd| {
        switch (cmd.cmd) {
            .Msg => {
                guestMsg(@truncate(cmd.data));
            },
            else => {
                usb.print("Guest Sent Unused Command: 0x{X} 0x{X}", .{ cmd.cmd, cmd.data });
            },
        }
    }
}
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    doPanic("{s}", .{msg});
    while (true) {}
}

// TODO: Explore panic override in RP2040 SDK (see panic.c)
// pub fn cpanic(msg: )

fn doPanic(comptime fmt: []const u8, args: anytype) void {
    while (true) {
        usb.tasks();
        if (usb.connected()) {
            usb.print("PANIC: " ++ fmt, args);
        }
    }
}

fn get_us_time() u64 {
    return hal.w_to_us_since_boot(hal.w_get_absolute_time());
}
/// 10s still alive messages
const upate_freq = 10_000_000;
var from_guest_spi: spi.PioAsyncSpiPeripheral = undefined;
var to_guest_spi: spi.PioAsyncSpiController = undefined;

var guest_vbus_state: bool = false;

export fn main() void {
    usb.initialize(true);
    // clock init
    const clk_ref = 0x5;
    hal.clock_gpio_init_int_frac(pins.GUESTCLK, clk_ref, 1, 0);
    // enable guest
    hal.gpio_init(pins.GUESTRUN);
    hal.gpio_set_dir(pins.GUESTRUN, true);
    hal.gpio_put(pins.GUESTRUN, true);
    // setup guest Vbus sense
    hal.gpio_init(pins.GUESTVBUS);
    hal.gpio_set_dir(pins.GUESTVBUS, false);
    // Watchdog pin not needed.
    from_guest_spi = spi.PioAsyncSpiPeripheral.init(pins.G2HSPI_D0, 1, pins.G2HSPI_READY, 8) catch {
        doPanic("Failed to initialize second SPI Peripheral...", .{});
        return;
    };
    to_guest_spi = spi.PioAsyncSpiController.init(pins.H2GSPI_D0, pins.H2GSPI_COUNT, pins.H2GSPI_CLK, pins.H2GSPI_READY, 8) catch {
        doPanic("Failed to initialize second SPI Controller...", .{});
        return;
    };

    // watchdog with enough time (hopefully to send messages in the case of a zig panic)
    hal.watchdog_enable(5000, true);
    while (true) {
        hal.watchdog_update();
        usb.tasks();
        handleUSBCmd();
        handleGuestCmd();
        if (guest_vbus_state != hal.gpio_get(pins.GUESTVBUS)) {
            guest_vbus_state = !guest_vbus_state;
            usb.print("Guest VBUS State Changed: {?}", .{guest_vbus_state});
        }
    }
}
