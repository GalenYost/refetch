pub const MemInfo = struct {
    const Field = std.meta.FieldEnum(MemInfo);

    pub const zero: MemInfo = .{ .MemTotal = 0, .MemAvailable = 0 };

    MemTotal: u64,
    MemAvailable: u64,

    pub fn read(errno: *linux.E, buffer: []u8) ?MemInfo {
        const open_rc = linux.open("/proc/meminfo", .{}, 0);
        const fd: linux.fd_t = switch (linux.errno(open_rc)) {
            .SUCCESS => @intCast(open_rc),
            else => |e| {
                errno.* = e;
                return null;
            },
        };

        defer _ = linux.close(fd);

        var fd_r: rdwr.Reader = .init(fd, buffer);
        const reader = &fd_r.interface;

        var set: std.EnumSet(MemInfo.Field) = .empty;
        var info: MemInfo = .zero;

        while (!set.eql(.full)) {
            const line = reader.takeDelimiter('\n') catch |err| switch (err) {
                error.StreamTooLong => return null,
                error.ReadFailed => {
                    errno.* = fd_r.err;
                    return null;
                },
            } orelse return null;

            var it = std.mem.tokenizeAny(u8, line, ": ");
            const field = it.next().?;
            const value = it.next() orelse continue;

            switch (std.meta.stringToEnum(MemInfo.Field, field) orelse continue) {
                inline else => |f| {
                    @field(info, @tagName(f)) = @divFloor(std.fmt.parseInt(u64, value, 10) catch 0, 1024);
                    set.insert(f);
                },
            }
        }

        return info;
    }
};

pub const CpuInfo = struct {
    const model_name_key = "model name\t: ";

    pub const fallback: CpuInfo = .{ .model_name = "Unknown" };

    model_name: []const u8,

    pub fn read(errno: *linux.E, buffer: []u8) ?CpuInfo {
        const open_rc = linux.open("/proc/cpuinfo", .{}, 0);
        const fd: linux.fd_t = switch (linux.errno(open_rc)) {
            .SUCCESS => @intCast(open_rc),
            else => |e| {
                errno.* = e;
                return null;
            },
        };

        defer _ = linux.close(fd);

        var fd_r: rdwr.Reader = .init(fd, buffer);
        const reader = &fd_r.interface;

        while (true) {
            const line = reader.takeDelimiter('\n') catch |err| switch (err) {
                error.StreamTooLong => return null,
                error.ReadFailed => {
                    errno.* = fd_r.err;
                    return null;
                },
            } orelse return null;

            if (std.mem.startsWith(u8, line, model_name_key))
                return .{ .model_name = line[model_name_key.len..] };
        }
    }
};

const linux = std.os.linux;

const rdwr = @import("rdwr.zig");
const std = @import("std");
