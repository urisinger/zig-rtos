const std = @import("std");
const targets = @import("build/targets.zig");
const qemu = @import("build/qemu.zig");
const utils = @import("build/utils.zig");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});

    // --- 1. Resolve Options ---
    const arch = b.option(std.Target.Cpu.Arch, "arch", "The target architecture") orelse .riscv32;
    const qemu_debug = b.option(u2, "debug-level", "QEMU debug level (0-3)") orelse 1;
    const qemu_monitor = b.option(bool, "monitor", "Enable QEMU monitor") orelse false;
    const qemu_args = b.option([]const u8, "qemu-args", "Extra QEMU args") orelse "";

    const kernel_target = b.resolveTargetQuery(targets.get(arch));

    const kernel_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = kernel_target,
        .optimize = optimize,
        .code_model = .large,
    });

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .use_llvm = true,
        .root_module = kernel_module,
    });

    kernel.setLinkerScript(b.path("linker.ld"));
    kernel.lto = .none;

    const config = b.addOptions();
    config.addOption([]const []const u8, "sources", try utils.getKernelSources(b));
    kernel.root_module.addOptions("config", config);

    b.installArtifact(kernel);

    // --- 4. Check Step (ZLS) ---
    const check_step = b.step("check", "Check if the project compiles");

    const kernel_check = b.addExecutable(.{
        .name = "kernel",
        .root_module = kernel_module,
    });
    kernel_check.setLinkerScript(b.path("linker.ld"));
    kernel_check.root_module.addOptions("config", config);

    check_step.dependOn(&kernel_check.step);

    // --- 5. Create ISO ---
    const rom = kernel.addObjCopy(.{ .format = .bin });
    const rom_install = b.addInstallBinFile(rom.getOutput(), "kernel.bin");

    rom.step.dependOn(&kernel.step);
    b.getInstallStep().dependOn(&rom_install.step);

    // --- 5. Run & Debug Steps (QEMU) ---
    const qemu_opts = qemu.QemuOptions{
        .arch = arch,
        .rom_install = rom_install,
        .debug_level = qemu_debug,
        .monitor = qemu_monitor,
        .extra_args = qemu_args,
        .gdb_server = false,
    };

    const run_step = b.step("run", "Run the OS in QEMU");
    run_step.dependOn(&qemu.createCommand(b, qemu_opts).step);

    const debug_step = b.step("debug", "Run the OS in QEMU with GDB server (-S -s)");
    var debug_opts = qemu_opts;
    debug_opts.gdb_server = true;
    debug_step.dependOn(&qemu.createCommand(b, debug_opts).step);

    // --- 6. GDB Step ---
    const gdb_step = b.step("gdb", "Run GDB client");
    const gdb_cmd = b.addSystemCommand(&.{"gdb"});
    gdb_cmd.addArtifactArg(kernel);
    gdb_cmd.addArgs(&.{ "-ex", "target remote localhost:1234", "-ex", "layout src" });
    gdb_cmd.stdio = .inherit;

    gdb_step.dependOn(&gdb_cmd.step);
    gdb_step.dependOn(b.getInstallStep());
}
