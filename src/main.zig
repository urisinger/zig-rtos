pub const serial = @import("drivers/uart/uart_16550.zig");
pub const arch = @import("arch/riscv32/mod.zig");
pub const klog = @import("utils/log.zig");
pub const sched = @import("sched/mod.zig");
pub const timer = @import("utils/timer.zig");
pub const Sched = sched.Sched;

pub var stdout = @import("utils/stdout.zig").writer();

const std = @import("std");
const log = std.log.scoped(.main);

pub const panic = klog.panic_handler;

const UART0_ADDR: usize = 0x10000000;

pub const std_options: std.Options = .{
    .logFn = klog.logFn,
    .log_level = .debug,
};

var scheduler: Sched = undefined;

const TrapFrame = arch.trap.TrapFrame;

pub export fn handleTimer(tf: *TrapFrame)  noreturn {
    const new_tf = scheduler.schedule(tf);
    arch.trap.contextSwitch(new_tf, false);
    unreachable;
}

var idle_task_mem: [1024 * 8]u8 align(16) = undefined;

pub export fn kmain(hartid: usize, dtb_ptr: usize) callconv(.c) noreturn {
    _ = hartid;
    _ = dtb_ptr;
    _ = handleTimer;

    arch.trap.init();

    const idle_task = sched.Task.init(&idle_task_mem, idle);
    scheduler = Sched.init(idle_task);

    serial.init(UART0_ADDR);

    serial.setBaudRate(0x0002);

    log.debug("\n--- NiggaOs Booting ---", .{});
    log.debug("Hardware: QEMU RISC-V 64 (virt)", .{});
    log.debug("Status: Stack initialized, BSS cleared.", .{});

    arch.instr.enableInterrupts();

    while (true) {}
}

pub fn idle() void {
    while (true) {}
}

pub export fn _start() linksection(".boot") callconv(.naked) noreturn {
    asm volatile (
        \\ la sp, stack_top
        \\
        \\ // Clear the BSS section
        \\ la t0, bss_start
        \\ la t1, bss_end
        \\ bgeu t0, t1, .Ldone
        \\ .Lloop:
        \\ sw zero, (t0)
        \\ addi t0, t0, 4
        \\ bltu t0, t1, .Lloop
        \\ .Ldone:
        \\
        \\ tail kmain
    );
}
