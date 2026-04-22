const std = @import("std");

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
    const table_addr = @intFromPtr(&vector_table);

    const mtvec_val = table_addr | 0x1;

    asm volatile ("csrw mtvec, %[val]"
        :
        : [val] "r" (mtvec_val),
    );

    asm volatile ("csrs mie, %[mask]"
        :
        : [mask] "r" (@as(usize, 0x880)),
    );
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

pub const SaveMode = enum {
    All, // Full save/restore (x1-x31, except SP)
    CalleeOnly, // Save/restore only s0-s11 (x8-x9, x18-x27)
    CallerOnly, // Save/restore only ra, t0-t6, a0-a7 (x1, x5-x7, x10-x17, x28-x31)
};

pub fn generateRegs(comptime op: []const u8, comptime mode: SaveMode) []const u8 {
    var buffer: [2048]u8 = undefined;
    var w = std.Io.Writer.fixed(&buffer);

    inline for (1..32) |i| {
        if (i == 2) continue; // Skip x2 (SP)

        const is_callee = switch (i) {
            8, 9, 18...27 => true, // s0-s11
            else => false,
        };
        const is_caller = switch (i) {
            1, 5...7, 10...17, 28...31 => true, // ra, t0-t6, a0-a7
            else => false,
        };

        const should_emit = switch (mode) {
            .All => true,
            .CalleeOnly => is_callee,
            .CallerOnly => is_caller,
        };

        if (should_emit) {
            w.print("{s}w x{d}, {d}(sp)\n", .{ op[0..1], i, (i - 1) * 4 }) catch unreachable;
        }
    }
    return w.buffered();
}

pub fn TrapHandler(comptime handler_name: []const u8, comptime context_switch: bool) type {
    return struct {
        const NAME = "entry_" ++ handler_name;
        fn entry() align(4) callconv(.naked) void {
            const mepc_off = @offsetOf(TrapFrame, "mepc");
            const mstatus_off = @offsetOf(TrapFrame, "mstatus");
            const frame_size = @sizeOf(TrapFrame);

            // If we are context switching, we MUST save everything.
            // If not, we only save the volatile/caller-saved registers.
            const save_mode = if (context_switch) SaveMode.All else SaveMode.CallerOnly;

            const asm_code = comptime std.fmt.comptimePrint(
                \\ addi sp, sp, -{d}
                \\ {s} // Save registers (temps or all)
                \\
                \\ csrr t0, mepc
                \\ sw t0, {d}(sp)
                \\ csrr t0, mstatus
                \\ sw t0, {d}(sp)
                \\
                \\ // Save the pre-trap SP into the TrapFrame's SP slot (offset 4)
                \\ addi t0, sp, {d}
                \\ sw t0, 4(sp)
                \\
                \\ mv a0, sp           // Arg 0: *TrapFrame
                \\ csrr a1, mcause     // Arg 1: mcause
                \\ csrr a2, mtval      // Arg 2: mtval
                \\ call {s}
                \\
                \\ // If context_switch is true, handler returned new SP in a0
                \\ {s} 
                \\
                \\ lw t0, {d}(sp)
                \\ csrw mstatus, t0
                \\ lw t0, {d}(sp)
                \\ csrw mepc, t0
                \\
                \\ {s} // Restore registers
                \\
                \\ lw sp, 4(sp) // Final SP restore
                \\ mret
            , .{
                frame_size,
                generateRegs("s", save_mode),
                mepc_off,
                mstatus_off,
                frame_size, // To calculate original SP
                handler_name,
                if (context_switch) "mv sp, a0" else "",
                mstatus_off,
                mepc_off,
                generateRegs("l", save_mode), // Restore exactly what we saved
            });

            asm volatile (asm_code);
        }
        comptime {
            @export(&entry, .{ .name = NAME, .linkage = .strong });
        }
    };
}

pub fn yield(current_sp: *usize, next_sp: usize) callconv(.naked) void {
    const mepc_off = @offsetOf(TrapFrame, "mepc");
    const mstatus_off = @offsetOf(TrapFrame, "mstatus");
    const frame_size = @sizeOf(TrapFrame);

    const asm_str = comptime std.fmt.comptimePrint(
        \\ addi sp, sp, -{d}
        \\ {s}
        \\ sw ra, {d}(sp)
        \\ csrr t0, mstatus
        \\ sw t0, {d}(sp)
        \\ addi t0, sp, {d}
        \\ sw t0, 4(sp)
        \\ sw sp, 0(a0)
        \\ mv sp, a1
        \\ lw t0, {d}(sp)
        \\ csrw mstatus, t0
        \\ lw t0, {d}(sp)
        \\ csrw mepc, t0
        \\ {s}
        \\ lw sp, 4(sp)
        \\ mret
    , .{ 
        frame_size, 
        generateRegs("s", .CalleeOnly), 
        mepc_off, 
        mstatus_off, 
        frame_size, 
        mstatus_off, 
        mepc_off, 
        generateRegs("l", .All) 
    });

    asm volatile (asm_str
        :
        : [current] "{a0}" (current_sp), 
          [next] "{a1}" (next_sp)
        : "memory"
    );
}

pub export fn vector_table() align(256) callconv(.naked) void {
    asm volatile (std.fmt.comptimePrint(
            \\ .option push
            \\ .option norvc
            \\ j {s} // 0: Exceptions
            \\ .align 2
            \\ j default_handler
            \\ .align 2
            \\ j default_handler
            \\ .align 2
            \\ j default_handler
            \\ .align 2
            \\ j default_handler
            \\ .align 2
            \\ j default_handler
            \\ .align 2
            \\ j default_handler
            \\ .align 2
            \\ j {s} // 7: Machine Timer (The scheduler entry)
            \\ .option pop
        , .{
            TrapHandler("handleTrap", false).NAME,
            TrapHandler("handleTimer", true).NAME,
        }));
}

pub export fn default_handler() callconv(.naked) void {
    asm volatile ("wfi; j default_handler");
}
