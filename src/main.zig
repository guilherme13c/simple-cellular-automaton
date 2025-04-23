const std = @import("std");
const log = std.log;

const cl = @import("cl.zig");
const sdl = @import("sdl3.zig");

const width: u32 = 2;
const height: u32 = 2;
const grid_size = width * height;

const window_width: i32 = 800;
const window_height: i32 = 600;

const cell_width: f32 = @as(f32, window_width) / @as(f32, width);
const cell_height: f32 = @as(f32, window_height) / @as(f32, height);

const padding: f32 = 0;

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

    const kernel = try cl.CLKernel.init(program, "update");
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
        window_width,
        window_height,
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

    const host_grid = init_grid: {
        var init_values: [grid_size]u32 = undefined;
        for (0..grid_size) |i| {
            init_values[i] = if (std.crypto.random.int(u8) % 4 == 0) 1 else 0;
        }
        break :init_grid init_values;
    };

    var event: sdl.c.SDL_Event = undefined;
    var running = true;
    while (running) {
        {
            try input_buffer.write(@ptrCast(@constCast(&host_grid)), command_queue);

            try kernel_call.call();

            try output_buffer.read(@ptrCast(@constCast(&host_grid)), command_queue);
        }

        {
            while (sdl.c.SDL_PollEvent(&event)) {
                if (event.type == sdl.c.SDL_EVENT_QUIT) {
                    running = false;
                }
            }

            _ = sdl.c.SDL_Delay(16);

            _ = sdl.c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
            _ = sdl.c.SDL_RenderClear(renderer);

            _ = sdl.c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);

            var x: f32 = 0;
            while (x <= window_width) : (x += cell_width) {
                _ = sdl.c.SDL_RenderLine(renderer, x, 0, x, window_height);
            }

            var y: f32 = 0;
            while (y <= window_height) : (y += cell_height) {
                _ = sdl.c.SDL_RenderLine(renderer, 0, y, window_width, y);
            }

            for (0..height) |row| {
                for (0..width) |col| {
                    const index = row * width + col;
                    if (host_grid[index] == 1) {
                        const rect = sdl.c.SDL_FRect{
                            .x = @as(f32, @floatFromInt(col)) * cell_width + padding,
                            .y = @as(f32, @floatFromInt(row)) * cell_height + padding,
                            .w = cell_width - 2 * padding,
                            .h = cell_height - 2 * padding,
                        };
                        _ = sdl.c.SDL_RenderFillRect(renderer, &rect);
                    }

                    std.debug.print("{}", .{host_grid[index]});
                }
            }

            _ = sdl.c.SDL_RenderPresent(renderer);
        }
    }
}
