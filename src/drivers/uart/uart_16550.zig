const root = @import("root");
const arch = root.arch;

const std = @import("std");


var uart: *volatile [8]u8 = undefined;

pub fn init(addr: usize) void {
    uart = @as(*volatile [8]u8, @ptrFromInt(addr));

    // Disable interrupts
    uart[1] = 0x00;

    // 8 bits, no parity, 1 stop bit
    uart[3] = 0x03;

    // Enable and clear FIFOs
    uart[2] = 0x07;
}

pub fn setBaudRate(divisor: u16) void {
    // Wait for transmitter to be idle
    while ((uart[5] & 0x40) == 0) {
        arch.instr.pause();
    }

    // Set DLAB to 1
    uart[3] |= 0x80;

    // Set new divisor
    uart[0] = @truncate(divisor & 0xFF);
    uart[1] = @truncate((divisor >> 8) & 0xFF);

    // Set DLAB to 0
    uart[3] &= ~@as(u8, 0x80);
}

pub fn print(msg: []const u8) void {
    const status = arch.enterCritical();
    for (msg) |c| {
        // Wait until THR is empty
        while ((uart[5] & 0x20) == 0) {
            arch.instr.pause();
        }
        uart[0] = c;
    }

    arch.exitCritical(status);
}
