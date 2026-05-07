pub const Writer = struct {
    fd: linux.fd_t,
    err: linux.E,
    interface: std.Io.Writer,

    pub fn init(fd: linux.fd_t, buffer: []u8) Writer {
        return .{
            .fd = fd,
            .err = .SUCCESS,
            .interface = .{ .buffer = buffer, .end = 0, .vtable = &.{ .drain = drain } },
        };
    }

    pub fn drain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        _ = .{ data, splat };
        const w: *Writer = @alignCast(@fieldParentPtr("interface", io_w));

        var seek: usize = 0;
        while (io_w.end != seek) {
            const rc = linux.write(w.fd, io_w.buffer[seek..].ptr, io_w.end - seek);
            switch (linux.errno(rc)) {
                .SUCCESS => seek += rc,
                else => |e| {
                    w.err = e;
                    return error.WriteFailed;
                },
            }
        }

        io_w.end = 0;
        return 0;
    }
};

pub const Reader = struct {
    fd: linux.fd_t,
    err: linux.E,
    interface: std.Io.Reader,

    pub fn init(fd: linux.fd_t, buffer: []u8) Reader {
        return .{
            .fd = fd,
            .err = .SUCCESS,
            .interface = .{ .buffer = buffer, .end = 0, .seek = 0, .vtable = &.{
                .stream = unreachableStream,
                .readVec = readVec,
            } },
        };
    }

    pub fn unreachableStream(
        io_r: *std.Io.Reader,
        io_w: *std.Io.Writer,
        limit: std.Io.Limit,
    ) std.Io.Reader.StreamError!usize {
        _ = .{ io_r, io_w, limit };
        unreachable;
    }

    pub fn readVec(io_r: *std.Io.Reader, vec: [][]u8) std.Io.Reader.Error!usize {
        _ = vec;
        const r: *Reader = @fieldParentPtr("interface", io_r);

        const buf = io_r.buffer[io_r.end..];
        const rc = linux.read(r.fd, buf.ptr, buf.len);
        switch (linux.errno(rc)) {
            .SUCCESS => return switch (rc) {
                0 => error.EndOfStream,
                else => fill: {
                    io_r.end += rc;
                    break :fill 0;
                },
            },
            else => |e| {
                r.err = e;
                return error.ReadFailed;
            },
        }
    }
};

const linux = std.os.linux;
const std = @import("std");
