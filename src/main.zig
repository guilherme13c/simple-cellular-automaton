const std = @import("std");
const log = std.log;

const cl = @import("cl.zig");
const sdl = @import("sdl3.zig");

const width: u32 = 800;
const height: u32 = 600;
const grid_size = width * height;

pub fn main() !void {
    const device = try cl.cl_get_device();

    const ctx = cl.c.clCreateContext(null, 1, &device, null, null, null);
    if (ctx == null) {
        log.err("Failed to create OpenCL context", .{});
        return;
    }
    defer _ = cl.c.clReleaseContext(ctx);

    const command_queue = try cl.CLQueue.init(ctx, device);
    defer command_queue.free();

    const update_kernel_src = @embedFile("kernel/update.cl");

    const program = try cl.CLProgram.init(ctx, device, update_kernel_src);
    defer program.free();

    const kernel = try cl.CLKernel.init(program, "update_grid");
    defer kernel.free();

    const input_buffer = try cl.CLBuffer.init(grid_size * @sizeOf(u32), ctx);
    defer input_buffer.free();

    const output_buffer = try cl.CLBuffer.init(grid_size * @sizeOf(u32), ctx);
    defer output_buffer.free();

    const ArgType = cl.CLKernelCall.ArgType;
    const args: [4]ArgType = .{
        ArgType{ .buffer = input_buffer },
        ArgType{ .buffer = output_buffer },
        ArgType{ .int = width },
        ArgType{ .int = height },
    };

    const kernel_call = cl.CLKernelCall{
        .args = @ptrCast(@constCast(&args)),
        .kernel = kernel,
        .queue = command_queue,
        .work_dim = 1,
        .global_work_size = .{ grid_size, 0, 0 },
        .local_work_size = .{ 64, 0, 0 },
    };

    if (!sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO)) {
        log.err("Failed to initialize SDL", .{});
        return;
    }
    defer sdl.c.SDL_Quit();

    const window = sdl.c.SDL_CreateWindow(
        "Simple Cellular Automaton",
        800,
        600,
        sdl.c.SDL_WINDOW_RESIZABLE | sdl.c.SDL_WINDOW_OPENGL,
    );
    if (window == null) {
        log.err("Failed to create SDL window", .{});
        return;
    }
    defer sdl.c.SDL_DestroyWindow(window);

    const renderer = sdl.c.SDL_CreateRenderer(window, null);
    if (renderer == null) {
        log.err("Failed to create SDL renderer", .{});
        return;
    }
    defer sdl.c.SDL_DestroyRenderer(renderer);

    var allocator = std.heap.page_allocator;
    const host_grid = try allocator.alloc(u8, grid_size);
    defer allocator.free(host_grid);

    for (host_grid) |*cell| {
        cell.* = if (std.crypto.random.int(u8) % 4 == 0) 1 else 0;
    }

    var event: sdl.c.SDL_Event = undefined;
    var running = true;
    while (running) {
        {
            try input_buffer.write(host_grid.ptr, command_queue);

            try kernel_call.call();

            try output_buffer.read(host_grid.ptr, command_queue);
        }

        while (sdl.c.SDL_PollEvent(&event)) {
            if (event.type == sdl.c.SDL_EVENT_QUIT) {
                running = false;
            }
        }

        _ = sdl.c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        _ = sdl.c.SDL_RenderClear(renderer);

        _ = sdl.c.SDL_RenderPresent(renderer);
    }
}
