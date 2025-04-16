const std = @import("std");
const log = std.log;

const cl = @import("cl.zig");

pub fn main() cl.CLError!void {
    const device = try cl.cl_get_device();

    const ctx = cl.c.clCreateContext(null, 1, &device, null, null, null);
    if (ctx == null) {
        log.err("Failed to create OpenCL context", .{});
        return;
    }
    defer _ = cl.c.clReleaseContext(ctx);
}
