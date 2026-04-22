const CLINT_BASE = 0x02000000;
const MTIME_REG = @as(*volatile u64, @ptrFromInt(CLINT_BASE + 0xBFF8));
const MTIMECMP_REG = @as(*volatile u64, @ptrFromInt(CLINT_BASE + 0x4000));

pub inline fn arm(interval_ticks: u64) void {
    const now = MTIME_REG.*;
    MTIMECMP_REG.* = now + interval_ticks;
}

pub inline fn freq() u64 {
    return 10_000_000;
}

pub inline fn get() u64 {
    return MTIME_REG.*;
}
