const root = @import("root");
const arch = root.arch;
const timer = arch.timer;

pub const arm = timer.arm;
pub const freq = timer.freq;
pub const now = timer.now;

pub inline fn msToTicks(ms: u64) u64 {
    return (ms * freq()) / 1000;
}

pub inline fn armMs(ms: u64) void {
    arm(msToTicks(ms));
}

/// Converts microseconds to hardware-specific ticks
pub inline fn usToTicks(us: u64) u64 {
    return (us * freq) / 1_000_000;
}


pub inline fn armUs(ms: u64) void {
    arm(usToTicks(ms));
}

/// Returns the time elapsed since a previous 'start_time'
pub inline fn elapsed(start_time: u64) u64 {
    return now() - start_time;
}

/// Simple busy-wait sleep (useful for early boot/drivers)
pub fn sleepBusy(ms: u64) void {
    const start = now();
    const target = msToTicks(ms);
    while (elapsed(start) < target) {
        asm volatile ("nop");
    }
}
