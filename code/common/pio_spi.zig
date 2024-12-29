/// Initially this will support two asyncronous SPI interfaces.  A write only and read only.
/// Write only SPI interface
///
const hal = @import("pico_sdk");
const commands = @import("commands.zig");
const cmds = commands.Cmds;

fn getTime_us() u64 {
    return hal.to_us_since_boot(hal.get_absolute_time());
}

const PioSPIError = error{
    FailedClaim,
    NodataPeriphrial,
    BufferOverflowPeriphrial,
    ResetTimeout,
};

const RESETWAIT_us = 1_000_000; // Start with 1 second
/// Sends a special Reset command, waits for valid reply to command - ignoring anything invalid
/// May timeout
pub fn reset_async_bus(tx: PioAsyncSpiController, rx: PioAsyncSpiPeripheral) PioSPIError.ResetTimeout!void {
    tx.send_cmd(cmds.ResetBus);
    // Wait for ResetComplete
    const timeout = getTime_us() + RESETWAIT_us;
    while (getTime_us() < timeout) {
        const cmd = rx.readCmd();
        if (cmd.cmd == cmds.ResetBus and cmd.data == 1) {
            break;
        }
    } else {
        return PioSPIError.ResetTimeout;
    }
}

/// Controller SPI that only sends data one way
pub const PioAsyncSpiController = struct {
    d0_pin: u32,
    count: u32,
    clk_pin: u32,
    ready_pin: u32,
    msg_size: u32,
    pio: hal.PIO = undefined,
    sm: c_uint = undefined,
    prg_offset: c_uint = undefined,
    pub fn init(d0_pin: u32, count: u32, clk_pin: u32, ready_pin: u32, msg_size: u32) !PioAsyncSpiController {
        var self: PioAsyncSpiController = .{ .d0_pin = d0_pin, .count = count, .clk_pin = clk_pin, .ready_pin = ready_pin, .msg_size = msg_size };
        // Setup SM
        const prg = hal.get_controller_prog(count);
        if (!hal.pio_claim_free_sm_and_add_program(prg, &self.pio, &self.sm, &self.prg_offset)) {
            return PioSPIError.FailedClaim;
        }
        hal.controller_program_init(self.pio, self.sm, self.prg_offset, self.d0_pin, self.count, self.clk_pin, self.ready_pin, self.msg_size);
        return self;
    }
    pub fn deinit(self: *PioAsyncSpiController) void {
        // should really stop SM here also I think...
        hal.pio_remove_program_and_unclaim_sm(hal.get_controller_prog(self.count), self.pio, self.sm, self.prg_offset);
        self.* = undefined;
    }
    /// Send one 32 bit word through the interface.
    /// Will block if FIFO is full
    /// everything above msg_size will be ignored...
    pub fn write(self: *PioAsyncSpiController, data: u32) void {
        // write directly to the FIFO
        hal.pio_sm_put_blocking(self.pio, self.sm, data);
    }
    pub fn send_cmd(self: *PioAsyncSpiController, cmd: commands.CmdPk) void {
        var buff: [5]u8 = undefined;
        const cmd_packed = commands.packCommand(&buff, cmd.cmd, cmd.data);
        for (cmd_packed) |v| {
            self.write(v);
        }
    }
};

const DATATIMEOUT = 1000000;
const CMDTIMEOUT = 10;

/// Peripheral SPI that only sends data one way
/// Maybe TODO: use a DMA buffer to ensure we don't loose messages but that assumes a bursty messaging
/// We really should plan to handle sustained speeds... anyway for this application it doesn't really matter - things need to happen in human time.
pub const PioAsyncSpiPeripheral = struct {
    d0_pin: u32,
    count: u32,
    ready_pin: u32,
    msg_size: u32,
    pio: hal.PIO = undefined,
    sm: c_uint = undefined,
    prg_offset: c_uint = undefined,
    shift: u5 = undefined,

    pub fn init(d0_pin: u32, count: u32, ready_pin: u32, msg_size: u32) !PioAsyncSpiPeripheral {
        var self: PioAsyncSpiPeripheral = .{ .d0_pin = d0_pin, .count = count, .ready_pin = ready_pin, .msg_size = msg_size };
        self.shift = 31 - @as(u5, @truncate(self.msg_size - 1));
        // Setup SM
        const prg = hal.get_peripheral_prog(count);
        if (!hal.pio_claim_free_sm_and_add_program(prg, &self.pio, &self.sm, &self.prg_offset)) {
            return PioSPIError.FailedClaim;
        }
        hal.peripheral_program_init(self.pio, self.sm, self.prg_offset, self.d0_pin, self.count, self.ready_pin, self.msg_size);
        return self;
    }
    pub fn deinit(self: *PioAsyncSpiPeripheral) void {
        // should really stop SM here also I think...
        hal.pio_remove_program_and_unclaim_sm(hal.get_peripheral_prog(self.count), self.pio, self.sm, self.prg_offset);
        self.* = undefined;
    }
    /// Read one 32 bit word through the interface.
    /// Error if not avalible or we lost something.
    pub fn read(self: *PioAsyncSpiPeripheral) !u32 {
        const fifo_count = hal.pio_sm_get_rx_fifo_level(self.pio, self.sm);
        return switch (fifo_count) {
            // 8 => PioSPIError.BufferOverflowPeriphrial, // ready pin handles this case for us now.
            0 => PioSPIError.NodataPeriphrial,
            else => hal.pio_sm_get(self.pio, self.sm) >> self.shift,
        };
    }
    pub fn getChar(self: *PioAsyncSpiPeripheral, timeout_us: u32) commands.CmdError!u32 {
        const timeout_time = getTime_us() + timeout_us;
        while (getTime_us() < timeout_time) {
            if (self.read()) |data| {
                return data;
            } else |err| switch (err) {
                PioSPIError.NodataPeriphrial => {
                    // Do nothing and wait for timeout
                },
                // PioSPIError.BufferOverflowPeriphrial => {
                //     return commands.CmdError.MalFormedCommand;
                // },
                else => unreachable,
            }
        } else {
            return commands.CmdError.ReadTimeout;
        }
    }
    pub fn readCmd(self: *PioAsyncSpiPeripheral) !commands.CmdPk {
        return commands.readNextCmdPtr(self, CMDTIMEOUT, DATATIMEOUT);
    }
};
