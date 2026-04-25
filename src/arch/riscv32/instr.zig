const std = @import("std");
const builtin = @import("builtin");

pub inline fn pause() void {
    if (comptime std.Target.riscv.featureSetHas(builtin.cpu.features, .zihintpause)) {
        asm volatile ("pause");
    } else {
        asm volatile ("nop");
    }
}

pub inline fn enableInterrupts() void {
    asm volatile (
        \\ csrsi mstatus, %[mask]
        :
        : [mask] "i" (1 << 3),
    );
}
