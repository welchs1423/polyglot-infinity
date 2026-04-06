const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const lib = b.addSharedLibrary(.{
        .name = "zigcore",
        .root_source_file = b.path("src/core.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);
}
