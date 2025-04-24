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
        .error_tracing = true,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    exe.linkLibC();
    exe.linkLibCpp();
    exe.linkSystemLibrary("OpenCL");
    exe.linkSystemLibrary("SDL3");

    b.installArtifact(exe);

    const clTests = b.addTest(.{
        .root_source_file = b.path("src/cl.zig"),
        .target = target,
        .optimize = optimize,
        .error_tracing = true,
    });
    clTests.linkLibC();
    clTests.linkLibCpp();
    clTests.linkSystemLibrary("OpenCL");
    clTests.linkSystemLibrary("SDL3");

    const runClTests = b.addRunArtifact(clTests);
    const tests = b.step("cl tests", "run opencl wrapper tests");
    tests.dependOn(&runClTests.step);
}
