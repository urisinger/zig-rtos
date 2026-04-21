const std = @import("std");
const serial = @import("dev/serial.zig");

pub const arch = @import("arch/riscv64/mod.zig");

const UART0_ADDR: usize = 0x10000000;

pub export fn _start() linksection(".boot") callconv(.naked) noreturn {
    asm volatile (
        \\ la sp, stack_top
        \\
        \\ # 2. Clear the BSS section
        \\ la t0, bss_start
        \\ la t1, bss_end
        \\ bgeu t0, t1, .Ldone
        \\ .Lloop:
        \\ sd zero, (t0)
        \\ addi t0, t0, 8
        \\ bltu t0, t1, .Lloop
        \\ .Ldone:
        \\
        \\ tail kmain
    );
}

pub export fn kmain(hartid: usize, dtb_ptr: usize) callconv(.c) noreturn {
    _ = hartid;
    _ = dtb_ptr;

    serial.init(UART0_ADDR);
    
    serial.print("\n--- NiggaOs Booting ---\n");
    serial.print("Hardware: QEMU RISC-V 64 (virt)\n");
    serial.print("Status: Stack initialized, BSS cleared.\n");

    while (true) {
    }
}

