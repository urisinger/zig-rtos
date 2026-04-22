const std = @import("std");
const root = @import("root");


pub fn logFn(comptime level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    const color = switch (level) {
        .err => "\x1b[31m", // Red for errors
        .warn => "\x1b[33m", // Yellow for warnings
        .info => "\x1b[32m", // Green for info
        .debug => "\x1b[36m", // Cyan for debug
    };

    const reset_color = "\x1b[0m";

    const scope_prefix = switch (scope) {
        std.log.default_log_scope => "",
        else => "(" ++ @tagName(scope) ++ ") ",
    };
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;

    const colored_prefix = color ++ prefix ++ reset_color;

    root.stdout.print(colored_prefix ++ format ++ "\n", args) catch return;
}

pub fn panic_handler(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    panic(msg);

    while (true) {}
}

pub fn panic(msg: []const u8) void {
    @branchHint(.cold);
    const log = std.log.scoped(.panic);
    log.err("kernel panic: {s}", .{msg});
}
