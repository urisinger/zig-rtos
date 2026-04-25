pub const serial = @import("drivers/uart/uart_16550.zig");
pub const arch = @import("arch/riscv32/mod.zig");
pub const utils = @import("utils/mod.zig");
const klog = utils.klog;
pub const sched = @import("sched/mod.zig");
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

pub var scheduler: Sched = undefined;

const TrapFrame = arch.trap.TrapFrame;

var idle_task_mem: [1024 * 4]u8 align(16) = undefined;

pub export fn handleTimer(tf: *TrapFrame) callconv(.c) *TrapFrame {
    return scheduler.schedule(tf);
}

var test_task_mem: [1024 * 4]u8 align(16) = undefined;
pub export fn kmain(hartid: usize, dtb_ptr: usize) callconv(.c) noreturn {
    _ = hartid;
    _ = dtb_ptr;
    _ = handleTimer;

    serial.init(UART0_ADDR);

    serial.setBaudRate(0x0002);

    arch.trap.init();
    const idle_task = sched.Task.initStatic(&idle_task_mem, idle);
    scheduler = Sched.init(idle_task);
    const test_task = sched.Task.initStatic(&test_task_mem, testTask);
    scheduler.addTask(test_task);

    log.debug("\n--- NiggaOs Booting ---", .{});
    log.debug("Hardware: QEMU RISC-V 64 (virt)", .{});
    log.debug("Status: Stack initialized, BSS cleared.", .{});

    scheduler.start();

    while (true) {}
}

pub fn idle() align(4) callconv(.c) void {
    while (true) {
        log.debug("i am idle lol", .{});
        scheduler.yeild();
    }
}

pub fn testTask() align(4) callconv(.c) void {
    while (true) {
        log.debug("yeilding now: ", .{});
        scheduler.yeild();
    }
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
