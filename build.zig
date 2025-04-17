const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .Debug,
    });

    const exe = b.addExecutable(.{
        .name = "simple-cellular-automaton",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkLibCpp();

    exe.linkSystemLibrary("OpenCL");

    exe.linkSystemLibrary("SDL3");

    b.installArtifact(exe);
}
