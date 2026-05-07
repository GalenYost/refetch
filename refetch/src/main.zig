const config = @import("config");
const color_reset = "\x1b[0m";

const logo_lines = split: {
    var lines: []const []const u8 = &.{};
    var it = std.mem.splitScalar(u8, config.logo, '\n');

    while (it.next()) |line|
        lines = lines ++ [1][]const u8{line};

    break :split lines;
};

pub const std_options: std.Options = .{
    .enable_segfault_handler = false,
    .signal_stack_size = null, // avoid sigaltstack(2) call.
};

const Env = struct {
    const Var = std.meta.FieldEnum(Env);

    SHELL: [:0]const u8 = "(unset)",
    TERM: [:0]const u8 = "(unset)",
    USER: [:0]const u8 = "root",
};

const System = struct {
    uts: linux.utsname,
    info: linux.Sysinfo,
    mem: proc.MemInfo,
    cpu: proc.CpuInfo,
    pretty_name: []const u8,
};

const Uptime = enum(u64) {
    _,

    pub fn format(uptime: Uptime, w: *std.Io.Writer) !void {
        const u = @intFromEnum(uptime);
        const hours = @divFloor(u, 3600);
        if (hours != 0)
            try w.print("{d} hours, ", .{hours});

        const minutes = @mod(@divFloor(u, 60), 60);
        if (hours != 0 or minutes != 0)
            try w.print("{d} minutes, ", .{minutes});

        const seconds = @mod(u, 60);
        try w.print("{d} seconds", .{seconds});
    }
};

pub inline fn main(init: std.process.Init.Minimal) noreturn {
    var env: Env = .{};
    var errno: linux.E = .SUCCESS;

    for (init.environ.block.view().slice) |entry| {
        const span = std.mem.span(entry);
        const i = std.mem.findScalar(u8, span, '=') orelse continue;
        const key, const value = .{ span[0..i], span[i + 1 ..] };

        switch (std.meta.stringToEnum(Env.Var, key) orelse continue) {
            inline else => |ev| @field(env, @tagName(ev)) = value,
        }
    }

    var uts: linux.utsname = undefined;
    _ = linux.uname(&uts);

    var sysinfo: linux.Sysinfo = undefined;
    _ = linux.sysinfo(&sysinfo);

    var cpu_info_buf: [1024]u8 = undefined;

    const cpu_info: proc.CpuInfo = proc.CpuInfo.read(&errno, &cpu_info_buf) orelse switch (errno) {
        .SUCCESS => .fallback,
        else => |e| fatal(e),
    };

    var mem_info_buf: [1024]u8 = undefined;

    const mem_info: proc.MemInfo = proc.MemInfo.read(&errno, &mem_info_buf) orelse switch (errno) {
        .SUCCESS => .zero,
        else => |e| fatal(e),
    };

    var os_release_buf: [1024]u8 = undefined;

    const pretty_name = etc.readOsPrettyName(&errno, &os_release_buf) orelse switch (errno) {
        .SUCCESS => "Unknown",
        else => |e| fatal(e),
    };

    var wr_buf: [1024]u8 = undefined;
    var fd_w: rdwr.Writer = .init(linux.STDOUT_FILENO, &wr_buf);

    printOutput(&fd_w.interface, &env, &.{
        .uts = uts,
        .mem = mem_info,
        .cpu = cpu_info,
        .info = sysinfo,
        .pretty_name = pretty_name,
    }) catch |err| switch (err) {
        error.WriteFailed => fatal(fd_w.err),
    };

    exit(0);
}

fn printOutput(writer: *std.Io.Writer, env: *const Env, sys: *const System) std.Io.Writer.Error!void {
    const lc = config.color;
    const ll = logo_lines;
    const cr = color_reset;

    try writer.print(
        "" ++
            lc ++ ll[0] ++ cr ++ "\t{s}@{s}\n" ++
            lc ++ ll[1] ++ cr ++ "\tDistribution:   {s}\n" ++
            lc ++ ll[2] ++ cr ++ "\tKernel:         {s} ({s})\n" ++
            lc ++ ll[3] ++ cr ++ "\tCPU:            {s}\n" ++
            lc ++ ll[4] ++ cr ++ "\tMemory:         {d} MiB / {d} MiB\n" ++
            lc ++ ll[5] ++ cr ++ "\tShell:          {s}\n" ++
            lc ++ ll[6] ++ cr ++ "\tTerminal:       {s}\n" ++
            lc ++ ll[7] ++ cr ++ "\tUptime:         {f}\n",
        .{
            // user@hostname
            env.USER,
            &sys.uts.nodename,
            // Distribution
            sys.pretty_name,
            // Kernel
            &sys.uts.sysname,
            &sys.uts.release,
            // CPU
            sys.cpu.model_name,
            // Memory
            sys.mem.MemTotal - sys.mem.MemAvailable,
            sys.mem.MemTotal,
            // Shell
            std.fs.path.basename(env.SHELL),
            // Terminal
            env.TERM,
            // Uptime
            @as(Uptime, @enumFromInt(sys.info.uptime)),
        },
    );

    try writer.flush();
}

fn fatal(err: linux.E) noreturn {
    var fmt_buf: [128]u8 = undefined;
    const fmt = switch (builtin.mode) {
        .Debug => std.fmt.bufPrint(&fmt_buf, "error: {t}\n", .{err}),
        else => std.fmt.bufPrint(&fmt_buf, "error: {d}\n", .{@intFromEnum(err)}),
    } catch exit(1);

    _ = linux.write(linux.STDERR_FILENO, fmt.ptr, fmt.len);
    exit(1);
}

const etc = @import("etc.zig");
const proc = @import("proc.zig");
const rdwr = @import("rdwr.zig");

const exit = std.process.exit;
const linux = std.os.linux;
const builtin = @import("builtin");
const std = @import("std");
