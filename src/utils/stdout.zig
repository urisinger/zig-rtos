const std = @import("std");
const Io = std.Io;
const Writer = Io.Writer;

const root = @import("root");
const serial = root.serial;

pub fn writer() Writer {
    return .{
        .vtable = &.{
            .drain = drain,
        },
        .buffer = &.{},
    };
}

pub fn drain(_: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
    var written: usize = 0;
    if (data.len == 0) return 0;
    for (data[0 .. data.len - 1]) |bytes| {
        serial.print(bytes);
        written += bytes.len;
    }

    const pattern = data[data.len - 1];
    for (0..splat) |_| {
        serial.print(pattern);
        written += pattern.len;
    }
    return written;
}
