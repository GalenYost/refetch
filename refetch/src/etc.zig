pub fn readOsPrettyName(errno: *linux.E, buffer: []u8) ?[]const u8 {
    const open_rc = linux.open("/etc/os-release", .{}, 0);
    const fd: linux.fd_t = switch (linux.errno(open_rc)) {
        .SUCCESS => @intCast(open_rc),
        else => |e| {
            errno.* = e;
            return null;
        },
    };

    defer _ = linux.close(fd);

    var fd_r: rdwr.Reader = .init(fd, buffer);
    return extractField(&fd_r.interface, "PRETTY_NAME") catch |err| switch (err) {
        error.EndOfStream => return "unknown os",
        error.ReadFailed => {
            errno.* = fd_r.err;
            return null;
        },
    };
}

fn extractField(reader: *std.Io.Reader, comptime name: []const u8) std.Io.Reader.Error!?[]const u8 {
    while (true) {
        const key = reader.takeDelimiter('=') catch |err| switch (err) {
            error.ReadFailed => |e| return e,
            error.StreamTooLong => return null,
        } orelse return null;

        const desired = std.mem.eql(u8, key, name);
        const value = reader.takeDelimiter('\n') catch |err| switch (err) {
            error.ReadFailed => |e| return e,
            error.StreamTooLong => return null,
        } orelse return null;

        if (desired)
            return unquote(value);
    }
}

fn unquote(maybe_quoted: []const u8) []const u8 {
    var start: usize = 0;
    var len: usize = maybe_quoted.len;
    if (len != 0) {
        if (maybe_quoted[0] == '"') start = 1;
        if (maybe_quoted[len - 1] == '"') len -= 1;
    }

    return maybe_quoted[start..len];
}

const linux = std.os.linux;

const rdwr = @import("rdwr.zig");
const std = @import("std");
