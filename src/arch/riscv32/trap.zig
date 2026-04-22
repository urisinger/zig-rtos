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

fn generateRegs(comptime op: []const u8, comptime temps_only: bool) []const u8 {
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    inline for (1..32) |i| {
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

pub fn TrapHandler(comptime handler_name: []const u8, comptime context_switch: bool) type {
    return struct {
        const NAME = "entry_" ++ handler_name;
        fn entry() align(4) callconv(.naked) void {
            const mepc_off = @offsetOf(TrapFrame, "mepc");
            const mstatus_off = @offsetOf(TrapFrame, "mstatus");
            const frame_size = @sizeOf(TrapFrame);

            const asm_code = comptime std.fmt.comptimePrint(
                \\ addi sp, sp, -{d}
                \\ {s} // Save registers (temps or all)
                \\
                \\ csrr t0, mepc
                \\ sw t0, {d}(sp)
                \\ csrr t0, mstatus
                \\ sw t0, {d}(sp)
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
                \\ mret
            , .{
                frame_size,
                generateRegs("s", !context_switch),
                mepc_off,
                mstatus_off,
                handler_name,
                if (context_switch) "mv sp, a0" else "",
                mstatus_off,
                mepc_off,
                generateRegs("l", !context_switch),
            });

            asm volatile (asm_code);
        }
        comptime {
            @export(&entry, .{ .name = NAME, .linkage = .strong });
        }
    };
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
