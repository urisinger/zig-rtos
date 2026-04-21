const std = @import("std");
const builtin = @import("builtin");

pub fn pause() void {
    if (comptime std.Target.riscv.featureSetHas(builtin.cpu.features, .zihintpause)) {
        asm volatile ("pause");
    } else {
        asm volatile ("nop");
    }
}
