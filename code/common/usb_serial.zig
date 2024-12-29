const std = @import("std");
const hal = @import("pico_sdk");
const tusb = hal;
const commands = @import("commands.zig");

const DATATIMEOUT = 1000000;
const CMDTIMEOUT = 10;
const itf = 0;

pub var DEBUG = true;
/// Initialize stdio and write first message
pub fn initialize(dbg: bool) void {
    hal.board_init();
    // init device stack on configured roothub port
    _ = hal.tud_init(hal.BOARD_TUD_RHPORT);
    print("Initialized!", .{});
    DEBUG = dbg;
}

fn get_us_time() u64 {
    return hal.to_us_since_boot(hal.get_absolute_time());
}

/// Should be called as often as possible to keep the related buffers from filling up.
pub fn tasks() void {
    tusb.tud_task_ext(0xFFFF_FFFF, false);
}

/// Return true if the stdio interface is connected else false.
pub fn connected() bool {
    return tusb.tud_cdc_connected();
}

pub fn getChar(timeout_us: u32) commands.CmdError!u32 {
    var char: u8 = undefined;
    var v: u32 = undefined;
    const timeout_end = get_us_time() + timeout_us;
    while (true) {
        v = tusb.tud_cdc_n_read(itf, &char, 1);
        if (v > 0) {
            return char;
        }
        if (get_us_time() > timeout_end) {
            return commands.CmdError.ReadTimeout;
        }
    }
}

pub fn readNextCmd() commands.CmdError!commands.CmdPk {
    return commands.readNextCmdPtr(@This(), CMDTIMEOUT, DATATIMEOUT);
}

var write_buf: [256]u8 = undefined;

/// Write the input string out throuhg stdio (will add newline at the end)
pub fn writeS(comptime fmt: []const u8, args: anytype) void {
    const count = std.fmt.count(fmt, args);
    if (count > (write_buf.len - 2)) {
        const msg = "String was too larg to write...";
        _ = tusb.tud_cdc_n_write(itf, msg, msg.len);
    } else {
        const msg = std.fmt.bufPrintZ(&write_buf, fmt, args) catch unreachable;
        const pointer: *const anyopaque = msg.ptr;
        _ = tusb.tud_cdc_n_write(itf, pointer, msg.len);
    }
    _ = tusb.tud_cdc_n_write_flush(itf);
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    writeS(fmt ++ "\n", args);
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (DEBUG) {
        print("DBG:" ++ fmt, args);
    }
}
