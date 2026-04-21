const std = @import("std");

pub fn getKernelSources(b: *std.Build) ![]const []const u8 {
    var sources_list = std.ArrayList([]const u8).empty;
    
    // Using build_root guarantees stable paths regardless of where zig build is invoked
    var dir = try b.build_root.handle.openDir(b.graph.io, "src/", .{ .iterate = true });
    defer dir.close(b.graph.io);

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next(b.graph.io)) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.path, ".zig")) {
            const path = try b.allocator.dupe(u8, entry.path);
            try sources_list.append(b.allocator, path);
        }
    }

    return sources_list.toOwnedSlice(b.allocator);
}
