const std = @import("std");
const intToEnum = std.meta.intToEnum;

/// Host USB Commands:
/// There are three commands types short (4bit), mid (16bit) and long (32bit)
/// The command struct is represented by u8 command and a u32 data (MSBs are zero'd for longer commands)
///
/// - if bits 7-6 are 0b0x it's a short comand with only 4 bits of data (8  short commands (x 16 data = 128 so all 256 code for first byte are accounted for))
/// - if bits 7-6 are 0b10 only two byte (16 bits) of data will be read (64 16 bit commands)
/// - if bits 7-6 are 0b11 four bytes (32 bits) of data will be read    (64 32 bit commands)
///
/// a reserved short command is 0x00.  This is always a no-op. Sending 5 of these commands should be enough to reset the parser to a known state - waiting for the next command byte.
pub const Cmds = enum(u8) {
    /// first command - echo back command
    Echo4 = 0x1,
    /// Restarts bootloader.
    ResetBus = 0x3, // data 0 is a request, data 1 is done.

    // last short command is 0x7
    // ___________________________________________________________________
    /// 16 bit commands start here - echo back command
    Echo16 = 0x81,
    /// data format: {index:u8, value: u8} where index represents one of the 6 slots.  If index==6 (7th) then update modifier.
    KeyBoardUpdate = 0x82,
    /// send ascii.  Mostly for debug
    Msg = 0x83,

    // _________________________________________________________________
    /// 32 bit commands start here Echo back the command
    Echo32 = 0xC1,
    DoPanic = 0xC2,
    /// Sometimes my system was apparently sending junk
    /// 0xC3 is less likely to accidentally be triggered.
    /// data 0xAAAA_AAAA: Host reset
    /// data 0x5555_5555: Guest Reset
    RestartToBootloader = 0xC3,
    /// [0:7] mouse type (rel/boot 0, 1 abs), [8:15] buttons, [16:23] vert, [24:31] hori
    MouseUpdate = 0xC5,
    /// [0:15] x pos, [16:31] y pos
    MousePosUpdate = 0xC6,
    _,
};

pub const CmdPk = struct {
    cmd: Cmds,
    data: u32,
};

pub const CmdError = error{
    ReadTimeout,
    MalFormedCommand,
    InvalidCommand,
};

/// Read next command out of buffer.  Returns error if no commands are avalible.
/// Function may return invalid enums.  So that needs to be handled at the upper level
/// The reasoning for this is that upper level code will need to handle the commands anyway and are better positioned to
/// Explain/handle the issue.
pub fn readNextCmd(comptime getChar: fn (timeout: u32) CmdError!u32, cmd_timeout: u32, data_timeout: u32) CmdError!CmdPk {
    // we expect that the next character out is a command
    var new_cmd: u8 = 0;
    while (true) {
        new_cmd = @truncate(try getChar(cmd_timeout));
        if (new_cmd != 0) {
            break;
        } // handle the onop case
    }
    var data: u32 = 0;
    if (new_cmd >> 7 == 1) {
        data += try getChar(data_timeout);
        data += try getChar(data_timeout) << 8;
        if ((new_cmd & 0b100_0000) > 0) {
            data += try getChar(data_timeout) << 16;
            data += try getChar(data_timeout) << 24;
        }
        return CmdPk{ .cmd = @enumFromInt(new_cmd), .data = data };
    } else {
        // single byte command
        return CmdPk{ .cmd = @enumFromInt(new_cmd >> 4), .data = new_cmd & 0xF };
    }
}

// fn asPointer(print: *const fn (str: []const u8) void) void {
//     print("hello from function pointer");
// }
pub fn readNextCmdPtr(self: anytype, cmd_timeout: u32, data_timeout: u32) CmdError!CmdPk {
    // we expect that the next character out is a command
    var new_cmd: u8 = 0;
    while (true) {
        new_cmd = @truncate(try self.getChar(cmd_timeout));
        if (new_cmd != 0) {
            break;
        } // handle the onop case
    }
    var data: u32 = 0;
    if (new_cmd >> 7 == 1) {
        data += try self.getChar(data_timeout);
        data += try self.getChar(data_timeout) << 8;
        if ((new_cmd & 0b100_0000) > 0) {
            data += try self.getChar(data_timeout) << 16;
            data += try self.getChar(data_timeout) << 24;
        }
        return CmdPk{ .cmd = @enumFromInt(new_cmd), .data = data };
    } else {
        // single byte command
        return CmdPk{ .cmd = @enumFromInt(new_cmd >> 4), .data = new_cmd & 0xF };
    }
}

/// input the command and data
/// output - into given buffer (buff) a series of u8 representing that command.
pub fn packCommand(buff: *[5]u8, cmd: Cmds, data: u32) []u8 {
    // TODO: is it better to return a slice - which will refrence the same buffer
    //       or return just the count/length?
    const cmd_n: u8 = @intFromEnum(cmd);
    if (cmd_n >> 7 == 1) {
        buff[0] = cmd_n;
        buff[1] = @truncate(data & 0xFF);
        buff[2] = @truncate((data >> 8) & 0xFF);
        if ((cmd_n & 0b100_0000) > 0) {
            buff[3] = @truncate((data >> 16) & 0xFF);
            buff[4] = @truncate((data >> 24) & 0xFF);
            return buff[0..5];
        } else {
            return buff[0..3];
        }
    } else {
        // single byte command & data
        buff[0] = (cmd_n & 0xF) << 4 | @as(u8, @truncate((data & 0xF)));
        return buff[0..1];
    }
}
