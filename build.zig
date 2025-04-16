const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "simple-cellular-automaton",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.addLibraryPath(.{ .cwd_relative = "/usr/local/cuda/lib64" });
    exe.linkSystemLibrary2("OpenCL", .{ .needed = true, });

    b.installArtifact(exe);
}
