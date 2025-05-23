const std = @import("std");
const log = std.log;

pub const c = @cImport({
    @cDefine("CL_TARGET_OPENCL_VERSION", "130");
    @cInclude("CL/cl.h");
});

pub const CLError = error{
    GetPlatformsFailed,
    GetPlatformInfoFailed,
    NoPlatformsFound,
    GetDevicesFailed,
    GetDeviceInfoFailed,
    NoDevicesFound,
    CreateContextFailed,
    CreateCommandQueueFailed,
    CreateProgramFailed,
    BuildProgramFailed,
    FreeProgramFailed,
    CreateKernelFailed,
    FreeKernelFailed,
    SetKernelArgFailed,
    EnqueueNDRangeKernelFailed,
    CreateBufferFailed,
    EnqueueWriteBufferFailed,
    EnqueueReadBufferFailed,
};

pub fn cl_get_device() CLError!c.cl_device_id {
    var platform_ids: [16]c.cl_platform_id = undefined;
    var platform_count: c.cl_uint = undefined;
    var status: c_int = undefined;

    status = c.clGetPlatformIDs(platform_ids.len, &platform_ids, &platform_count);
    if (status != c.CL_SUCCESS) {
        return CLError.GetPlatformsFailed;
    }

    for (platform_ids[0..platform_count]) |id| {
        var name: [1024]u8 = undefined;
        var name_len: usize = undefined;

        status = c.clGetPlatformInfo(id, c.CL_PLATFORM_NAME, name.len, &name, &name_len);
        if (status != c.CL_SUCCESS) {
            return CLError.GetPlatformInfoFailed;
        }
    }

    if (platform_count == 0) {
        return CLError.NoPlatformsFound;
    }

    var device_ids: [16]c.cl_device_id = undefined;
    var device_count: c.cl_uint = undefined;

    status = c.clGetDeviceIDs(platform_ids[0], c.CL_DEVICE_TYPE_ALL, device_ids.len, &device_ids, &device_count);
    if (status != c.CL_SUCCESS) {
        return CLError.GetDevicesFailed;
    }

    for (device_ids[0..device_count]) |id| {
        var name: [1024]u8 = undefined;
        var name_len: usize = undefined;

        status = c.clGetDeviceInfo(id, c.CL_DEVICE_NAME, name.len, &name, &name_len);
        if (status != c.CL_SUCCESS) {
            return CLError.GetDeviceInfoFailed;
        }
    }

    if (device_count == 0) {
        return CLError.NoDevicesFound;
    }

    return device_ids[0];
}

pub const CLBuffer = struct {
    const Self = @This();

    ctx: c.cl_context,
    d_buff: c.cl_mem,
    size: usize,

    pub fn init(size: usize, ctx: c.cl_context) CLError!CLBuffer {
        const input_buffer = c.clCreateBuffer(ctx, c.CL_MEM_READ_WRITE, size, null, null);
        if (input_buffer == null) {
            return CLError.CreateBufferFailed;
        }
        return .{ .ctx = ctx, .d_buff = input_buffer.?, .size = size };
    }

    pub fn free(self: Self) void {
        if (c.clReleaseMemObject(self.d_buff) != c.CL_SUCCESS) {
            std.log.err("Error on buffer free. {any}", .{self});
        }
    }

    pub fn read(self: Self, h_buff: ?*anyopaque, cmd_queue: CLQueue) CLError!void {
        if (c.clEnqueueReadBuffer(
            cmd_queue.queue,
            self.d_buff,
            c.CL_TRUE,
            0,
            self.size,
            h_buff,
            0,
            null,
            null,
        ) != c.CL_SUCCESS) {
            return CLError.EnqueueReadBufferFailed;
        }
    }

    pub fn write(self: Self, h_buff: ?*const anyopaque, cmd_queue: CLQueue) CLError!void {
        if (c.clEnqueueWriteBuffer(
            cmd_queue.queue,
            self.d_buff,
            c.CL_TRUE,
            0,
            self.size,
            h_buff,
            0,
            null,
            null,
        ) != c.CL_SUCCESS) {
            return CLError.EnqueueWriteBufferFailed;
        }
    }
};

pub const CLQueue = struct {
    const Self = @This();

    queue: c.cl_command_queue,

    pub fn init(ctx: c.cl_context, device: c.cl_device_id) CLError!Self {
        const command_queue = c.clCreateCommandQueue(ctx, device, 0, null); // future: last arg is error code
        if (command_queue == null) {
            return CLError.CreateCommandQueueFailed;
        }
        return .{ .queue = command_queue };
    }

    pub fn free(self: Self) void {
        _ = c.clFlush(self.queue);
        _ = c.clFinish(self.queue);
        _ = c.clReleaseCommandQueue(self.queue);
    }
};

test "test OpenCL memory buffer" {
    const device = try cl_get_device();
    const ctx = c.clCreateContext(null, 1, &device, null, null, null); // future: last arg is error code
    if (ctx == null) {
        return CLError.CreateContextFailed;
    }
    defer _ = c.clReleaseContext(ctx);

    const hbuff_write: [3]u8 = .{ 1, 2, 3 };
    var hbuff_read: [3]u8 = undefined;

    const queue = try CLQueue.init(ctx, device);
    var dbuff = try CLBuffer.init(3, ctx);
    defer {
        dbuff.free();
        queue.free();
    }

    try dbuff.write(&hbuff_write, queue);
    try dbuff.read(&hbuff_read, queue);
    _ = c.clFlush(queue.queue);
    _ = c.clFinish(queue.queue);

    try std.testing.expectEqual(1, hbuff_read[0]);
    try std.testing.expectEqual(2, hbuff_read[1]);
    try std.testing.expectEqual(3, hbuff_read[2]);
}

pub const CLProgram = struct {
    const Self = @This();

    program: c.cl_program,

    pub fn init(ctx: c.cl_context, device: c.cl_device_id, program_src_c: []const u8) CLError!Self {
        const program = c.clCreateProgramWithSource(ctx, 1, @ptrCast(@constCast(&program_src_c.ptr)), null, null);
        if (program == null) {
            return CLError.CreateProgramFailed;
        }
        if (c.clBuildProgram(program, 1, &device, null, null, null) != c.CL_SUCCESS) {
            return CLError.BuildProgramFailed;
        }
        return .{ .program = program };
    }

    pub fn free(self: Self) void {
        if (c.clReleaseProgram(self.program) != c.CL_SUCCESS) {
            std.log.err("Error on program free. {any}", .{self});
        }
    }
};

test "test OpenCL program" {
    const program_src =
        \\__kernel void square_array(__global int* input_array, __global int* output_array) {
        \\    int i = get_global_id(0);
        \\    int value = input_array[i];
        \\    output_array[i] = value * value;
        \\}
    ;

    const device = try cl_get_device();
    const ctx = c.clCreateContext(null, 1, &device, null, null, null); // future: last arg is error code
    if (ctx == null) {
        return CLError.CreateContextFailed;
    }
    defer _ = c.clReleaseContext(ctx);

    const program = try CLProgram.init(ctx, device, program_src);
    program.free();
}

pub const CLKernel = struct {
    const Self = @This();

    kernel: c.cl_kernel,

    pub fn init(program: CLProgram, kernel_name: []const u8) CLError!CLKernel {
        const kernel = c.clCreateKernel(program.program, @ptrCast(kernel_name), null);
        if (kernel == null) {
            return CLError.CreateKernelFailed;
        }
        return .{ .kernel = kernel };
    }

    pub fn free(self: Self) void {
        if (c.clReleaseKernel(self.kernel) != c.CL_SUCCESS) {
            std.log.err("Error on kernel free. {any}", .{self});
        }
    }
};

pub const CLKernelCall = struct {
    const Self = @This();
    pub const ArgType = union(enum) {
        int: i32,
        uint: u32,
        ushort: u16,
        float: f32,
        buffer: CLBuffer,
    };

    kernel: CLKernel,
    queue: CLQueue,

    args: []ArgType,
    work_dim: u32,
    global_work_size: [3]usize,
    local_work_size: [3]usize,

    pub fn call(self: Self) CLError!void {
        for (self.args, 0..) |arg, i| {
            switch (arg) {
                .int => |v| {
                    if (c.clSetKernelArg(self.kernel.kernel, @intCast(i), @sizeOf(i32), &v) != c.CL_SUCCESS) {
                        return CLError.SetKernelArgFailed;
                    }
                },
                .uint => |v| {
                    if (c.clSetKernelArg(self.kernel.kernel, @intCast(i), @sizeOf(u32), &v) != c.CL_SUCCESS) {
                        return CLError.SetKernelArgFailed;
                    }
                },
                .ushort => |v| {
                    if (c.clSetKernelArg(self.kernel.kernel, @intCast(i), @sizeOf(u16), &v) != c.CL_SUCCESS) {
                        return CLError.SetKernelArgFailed;
                    }
                },
                .float => |v| {
                    if (c.clSetKernelArg(self.kernel.kernel, @intCast(i), @sizeOf(f32), &v) != c.CL_SUCCESS) {
                        return CLError.SetKernelArgFailed;
                    }
                },
                .buffer => |v| {
                    if (c.clSetKernelArg(self.kernel.kernel, @intCast(i), @sizeOf(c.cl_mem), @ptrCast(&v.d_buff)) != c.CL_SUCCESS) {
                        return CLError.SetKernelArgFailed;
                    }
                },
            }
        }
        const errEnqueueKernel = c.clEnqueueNDRangeKernel(
            self.queue.queue,
            self.kernel.kernel,
            self.work_dim,
            null,
            &self.global_work_size,
            &self.local_work_size,
            0,
            null,
            null,
        );
        if (errEnqueueKernel != c.CL_SUCCESS) {
            std.debug.print("{}\n", .{errEnqueueKernel});
            return CLError.EnqueueNDRangeKernelFailed;
        }
    }
};

test "test OpenCL kernel" {
    const program_src =
        \\__kernel void square_array(__global int* input_array, __global int* output_array) {
        \\    int i = get_global_id(0);
        \\    int value = input_array[i];
        \\    output_array[i] = value * value;
        \\}
    ;

    const device = try cl_get_device();
    const ctx = c.clCreateContext(null, 1, &device, null, null, null);
    if (ctx == null) {
        return CLError.CreateContextFailed;
    }
    defer _ = c.clReleaseContext(ctx);

    const program = try CLProgram.init(ctx, device, program_src);
    defer program.free();
    const kernel = try CLKernel.init(program, "square_array");
    defer kernel.free();
}

test "test OpenCL kernel call" {
    const program_src =
        \\__kernel void square_array(__global int* input_array, __global int* output_array) {
        \\    int i = get_global_id(0);
        \\    int value = input_array[i];
        \\    output_array[i] = value * value;
        \\}
    ;

    const device = try cl_get_device();
    const ctx = c.clCreateContext(null, 1, &device, null, null, null);
    if (ctx == null) {
        return CLError.CreateContextFailed;
    }
    defer _ = c.clReleaseContext(ctx);
    const queue = try CLQueue.init(ctx, device);

    const program = try CLProgram.init(ctx, device, program_src);
    defer program.free();
    const kernel = try CLKernel.init(program, "square_array");
    defer kernel.free();

    var input_array = init: {
        var init_value: [1024]i32 = undefined;
        for (0..1024) |i| {
            init_value[i] = @as(i32, @intCast(i));
        }
        break :init init_value;
    };
    const input_buffer = try CLBuffer.init(1024 * @sizeOf(i32), ctx);
    defer input_buffer.free();
    try input_buffer.write(&input_array, queue);
    const output_buffer = try CLBuffer.init(1024 * @sizeOf(i32), ctx);
    defer output_buffer.free();

    const ArgType = CLKernelCall.ArgType;
    const args: [2]ArgType = .{
        ArgType{ .buffer = input_buffer },
        ArgType{ .buffer = output_buffer },
    };

    const kernel_call: CLKernelCall = .{
        .kernel = kernel,
        .queue = queue,
        .args = @ptrCast(@constCast(&args)),
        .global_work_size = .{ input_array.len, 0, 0 },
        .local_work_size = .{ 64, 0, 0 },
        .work_dim = 1,
    };
    try kernel_call.call();

    var output_array: [1024]i32 = undefined;
    try output_buffer.read(&output_array, queue);
    for (output_array, 0..) |val, i| {
        if (i % 100 == 0) {
            try std.testing.expect(val == (i * i));
        }
    }
}
