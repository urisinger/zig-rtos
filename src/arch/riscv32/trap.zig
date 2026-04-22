const std = @import("std");

const InterruptMode = enum(u2) {
    Direct = 0,
    Vectored = 1,
};

const InterruptEnable = packed struct(usize) {
    usie: u1 = 0, // bit 0
    ssie: u1 = 0, // bit 1
    _r0: u1 = 0,
    msie: u1 = 0, // bit 3
    utie: u1 = 0, // bit 4
    stie: u1 = 0, // bit 5
    _r1: u1 = 0,
    mtie: u1 = 0, // bit 7
    ueie: u1 = 0, // bit 8
    seie: u1 = 0, // bit 9
    _r2: u1 = 0,
    meie: u1 = 0, // bit 11
    _rest: u20 = 0,
};

pub fn init() void {
    const ptr = @intFromPtr(&trap_entry);

    if (ptr & 0b11 != 0) {
        @panic("Trap handler must be 4-byte aligned!");
    }

    const val = ptr | @intFromEnum(InterruptMode.Direct);
    asm volatile ("csrw mtvec, %[addr]"
        :
        : [addr] "r" (val),
    );

    // Enable Machine External Interrupts and Machine Timer Interrupts
    const enabled = InterruptEnable{
        .mtie = 1,
        .meie = 1,
    };
    asm volatile ("csrs mie, %[mask]"
        :
        : [mask] "r" (@as(usize, @bitCast(enabled))),
    );
}

fn generateRegs(comptime op: []const u8, comptime temps_only: bool, comptime skip_t0_t1: bool) []const u8 {
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    inline for (1..32) |i| {
        // x5 is t0, x6 is t1. We skip them if requested because they are saved manually.
        if (skip_t0_t1 and (i == 5 or i == 6)) continue;
        if (i == 2) continue;

        // RISC-V Temporary (Caller-Saved) Registers:
        // x1 (ra), x5-x7 (t0-t2), x10-x17 (a0-a7), x28-x31 (t3-t6)
        const is_temp = switch (i) {
            1, 5...7, 10...17, 28...31 => true,
            else => false,
        };

        if (!temps_only or is_temp) {
            writer.print("{s}w x{d}, {d}(sp)\n", .{ op[0..1], i, (i - 1) * 4 }) catch unreachable;
        }
    }
    return writer.buffered();
}

pub const TrapFrame = struct {
    regs: [31]usize,
    mepc: usize,
    mstatus: usize,

    pub fn init(self: *TrapFrame, entry: usize) void {
        self.mstatus = 0x80;
        self.mepc = entry;
    }
};

pub export fn trap_entry() align(4) callconv(.naked) void {
    const mepc_off = @offsetOf(TrapFrame, "mepc");
    const mstatus_off = @offsetOf(TrapFrame, "mstatus");
    const frame_size = @sizeOf(TrapFrame);

    // Offset for t0 (x5) and t1 (x6)
    const t0_off = (5 - 1) * 4;
    const t1_off = (6 - 1) * 4;

    const asm_code = comptime std.fmt.comptimePrint(
        \\ addi sp, sp, -{d}
        \\ sw t0, {d}(sp) // Save t0 immediately
        \\ sw t1, {d}(sp) // Save t1 immediately
        \\
        \\ csrr t0, mcause
        \\ li t1, 0x80000007 // Mask for Timer Interrupt ID (assuming 64-bit)
        \\ beq t0, t1, slow_path
        \\ j fast_path
        \\
        \\ fast_path:
        \\ {s} // Save remaining temp registers
        \\ csrr t0, mepc
        \\ sw t0, {d}(sp)
        \\ csrr t0, mstatus
        \\ sw t0, {d}(sp)
        \\
        \\ mv a0, sp        // arg0: tf
        \\ csrr a1, mcause  // arg1: mcause
        \\ csrr a2, mtval   // arg2: mtval
        \\ call handleTrap
        \\
        \\ lw t0, {d}(sp)
        \\ csrw mstatus, t0
        \\ lw t0, {d}(sp)
        \\ csrw mepc, t0
        \\ {s} // Restore remaining temp registers
        \\ lw t0, {d}(sp) // Restore t0
        \\ lw t1, {d}(sp) // Restore t1
        \\ addi sp, sp, {d}
        \\ mret
        \\
        \\ slow_path:
        \\ {s} // Save remaining ALL registers (s2-s11, etc)
        \\ csrr t0, mepc
        \\ sw t0, {d}(sp)
        \\ csrr t0, mstatus
        \\ sw t0, {d}(sp)
        \\
        \\ mv a0, sp // arg0: tf
        \\ call handleTimer
        \\ // No return from handleTimer, it will jump to contextSwitch
    , .{
        frame_size,
        t0_off,
        t1_off,

        // Fast Path arguments
        generateRegs("s", true, true), // Save temps only, skip t0/t1
        mepc_off,
        mstatus_off,
        mstatus_off,
        mepc_off,
        generateRegs("l", true, true), // Restore temps only, skip t0/t1
        t0_off,
        t1_off,
        frame_size,

        // Slow Path arguments
        generateRegs("s", false, true), // Save ALL, skip t0/t1
        mepc_off,
        mstatus_off,
    });

    asm volatile (asm_code);
}

pub inline fn contextSwitch(tf: *TrapFrame, save: bool) void {
    const mepc_off = @offsetOf(TrapFrame, "mepc");
    const mstatus_off = @offsetOf(TrapFrame, "mstatus");
    const frame_size = @sizeOf(TrapFrame);

    const asm_code = comptime std.fmt.comptimePrint(
        \\ // No 'mv sp, a0' needed; we tell the compiler to put 'tf' into 'sp'
        \\ 
        \\ lw t0, {d}(sp)
        \\ csrw mstatus, t0
        \\ lw t0, {d}(sp)
        \\ csrw mepc, t0
        \\ 
        \\ {s} // Restore ALL 31 registers
        \\ 
        \\ addi sp, sp, {d}
        \\ mret
    , .{
        mstatus_off,
        mepc_off,
        generateRegs("l", false, false),
        frame_size,
    });

    if (save) {
        asm volatile (asm_code
            :
            : [tf] "{sp}" (tf),
            : .{ .x1 = true, .x2 = true, .x3 = true, .x4 = true, .x5 = true, .x6 = true, .x7 = true, .x8 = true, .x9 = true, .x10 = true, .x11 = true, .x12 = true, .x13 = true, .x14 = true, .x15 = true, .x16 = true, .x17 = true, .x18 = true, .x19 = true, .x20 = true, .x21 = true, .x22 = true, .x23 = true, .x24 = true, .x25 = true, .x26 = true, .x27 = true, .x28 = true, .x29 = true, .x30 = true, .x31 = true, .memory = true });
    } else {
        asm volatile (asm_code
            :
            : [tf] "{sp}" (tf),
        );
    }
}
