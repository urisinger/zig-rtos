const std = @import("std");

pub fn get(arch: std.Target.Cpu.Arch) std.Target.Query {
    const enabled_features = std.Target.Cpu.Feature.Set.empty;
    var disabled_features = std.Target.Cpu.Feature.Set.empty;

    switch (arch) {
        .aarch64 => {
            const Feature = std.Target.aarch64.Feature;
            disabled_features.addFeature(@intFromEnum(Feature.fp_armv8));
            disabled_features.addFeature(@intFromEnum(Feature.crypto));
            disabled_features.addFeature(@intFromEnum(Feature.neon));
        },
        .riscv64 => {
            const Feature = std.Target.riscv.Feature;
            disabled_features.addFeature(@intFromEnum(Feature.d));
        },
        .riscv32 => {
            const Feature = std.Target.riscv.Feature;
            disabled_features.addFeature(@intFromEnum(Feature.d));
        },
        else => std.debug.panic("Unsupported architecture: {s}", .{@tagName(arch)}),
    }

    return .{
        .cpu_arch = arch,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = enabled_features,
        .cpu_features_sub = disabled_features,
    };
}

