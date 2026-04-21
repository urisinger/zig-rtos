const std = @import("std");

pub const QemuOptions = struct {
    arch: std.Target.Cpu.Arch,
    rom_install: *std.Build.Step.InstallFile,
    debug_level: u2,
    monitor: bool,
    extra_args: []const u8,
    gdb_server: bool,
};

pub fn createCommand(b: *std.Build, opts: QemuOptions) *std.Build.Step.Run {
    const qemu_bin = switch (opts.arch) {
        .aarch64 => "qemu-system-aarch64",
        .riscv64 => "qemu-system-riscv64",
        else => std.debug.panic("Unsupported architecture for ROM: {s}", .{@tagName(opts.arch)}),
    };

    const qemu_cmd = b.addSystemCommand(&.{qemu_bin});
    
    qemu_cmd.addArgs(&.{
        "-machine", "virt",
        "-cpu", "max",
        "-m", "128M",
        "-serial", "mon:stdio",
        "-nographic",
    });

    if (opts.monitor) {
        qemu_cmd.addArgs(&.{ "-monitor", "unix:qemu-monitor.sock,server,nowait" });
    }

    const bin_path = b.getInstallPath(.bin, opts.rom_install.dest_rel_path);

    qemu_cmd.addArgs(&.{ "-bios", bin_path });

    if (opts.gdb_server) {
        qemu_cmd.addArgs(&.{ "-S", "-s" });
    }

    switch (opts.debug_level) {
        0 => {},
        1 => qemu_cmd.addArgs(&.{ "-d", "guest_errors" }),
        2 => qemu_cmd.addArgs(&.{ "-d", "cpu_reset,guest_errors,unimp" }),
        3 => qemu_cmd.addArgs(&.{ "-d", "int,cpu_reset,guest_errors,in_asm" }),
    }

    if (opts.extra_args.len > 0) {
        var it = std.mem.tokenizeAny(u8, opts.extra_args, " ");
        while (it.next()) |arg| {
            qemu_cmd.addArg(arg);
        }
    }

    qemu_cmd.stdio = .inherit;
    qemu_cmd.step.dependOn(&opts.rom_install.step);

    return qemu_cmd;
}
