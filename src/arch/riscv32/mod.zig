pub const instr = @import("instr.zig");
pub const trap = @import("trap.zig");
pub const clint = @import("clint.zig");
pub const timer = clint;

const std = @import("std");
const log = std.log;

const root = @import("root");
const serial = root.serial;
const TrapFrame = trap.TrapFrame;

pub const Mcause = enum(usize) {
    // Exceptions
    instruction_address_misaligned = 0,
    instruction_access_fault = 1,
    illegal_instruction = 2,
    breakpoint = 3,
    load_address_misaligned = 4,
    load_access_fault = 5,
    store_address_misaligned = 6,
    store_access_fault = 7,
    environment_call_from_m = 11,

    // Interrupts (High bit set)
    machine_software_interrupt = 0x80000000 | 3,
    machine_timer_interrupt = 0x80000000 | 7,
    machine_external_interrupt = 0x80000000 | 11,

    _,

    pub fn fromValue(val: usize) Mcause {
        return @enumFromInt(val);
    }
};

export fn handleTrap(tf: *TrapFrame, mcause: usize, mtval: usize) callconv(.c) void {
    _ = tf;
    const cause = Mcause.fromValue(mcause);

    switch (cause) {
        .machine_timer_interrupt => {
            @panic("Timer interrupt should be handled in trap handler");
        },
        .illegal_instruction => {
            log.err("Illegal instruction at: 0x{x}", .{mtval});
            @panic("Illegal instruction");
        },
        else => {
            log.warn("Unhandled trap: {any}", .{cause});
            @panic("Unhandled trap");
        },
    }

}

pub inline fn enterCritical() usize {
    // Read mstatus, then clear the MIE bit (bit 3)
    return asm volatile (
        \\ csrrc a0, mstatus, %[mask]
        : [ret] "={a0}" (-> usize),
        : [mask] "i" (1 << 3),
    );
}

pub inline fn exitCritical(prev_status: usize) void {
    // We only want to restore the MIE bit if it was previously enabled
    const mie_bit = prev_status & (1 << 3);

    if (mie_bit != 0) {
        asm volatile (
            \\ csrsi mstatus, %[mask]
            :
            : [mask] "i" (1 << 3),
        );
    }
}
