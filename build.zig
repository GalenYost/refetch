pub fn build(b: *Build) void {
    const exe = b.addExecutable(.{
        .name = "refetch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("refetch/src/main.zig"),
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
            .single_threaded = true,
        }),
    });

    exe.stack_size = 0; // avoid prlimit64(2) call.
    exe.root_module.addAnonymousImport("config", .{ .root_source_file = b.path("refetch/config.zon") });

    b.installArtifact(exe);
    b.step("refetch", "print system information").dependOn(&b.addRunArtifact(exe).step);
}

const Build = std.Build;
const std = @import("std");
