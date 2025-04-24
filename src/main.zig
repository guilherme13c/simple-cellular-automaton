const std = @import("std");
const log = std.log;

const cl = @import("cl.zig");
const sdl = @import("sdl3.zig");

const window_width: i32 = 800;
const window_height: i32 = 600;

const padding: f32 = 0;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const initial_state = try load_initial_state(allocator, "src/initial/planer.txt");

    const width: u32 = initial_state.width;
    const height: u32 = initial_state.height;
    const grid_size = width * height;

    const cell_width: f32 = @as(f32, window_width) / @as(f32, @floatFromInt(width));
    const cell_height: f32 = @as(f32, window_height) / @as(f32, @floatFromInt(height));

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
    var args: [4]ArgType = .{
        ArgType{ .buffer = input_buffer },
        ArgType{ .buffer = output_buffer },
        ArgType{ .uint = width },
        ArgType{ .uint = height },
    };

    const kernel_call = cl.CLKernelCall{
        .args = @ptrCast(&args),
        .kernel = kernel,
        .queue = command_queue,
        .work_dim = 1,
        .global_work_size = .{ 256, 0, 0 },
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

    var host_input_grid: []bool = try allocator.alloc(bool, grid_size);
    defer allocator.free(host_input_grid);

    var host_output_grid: []bool = try allocator.alloc(bool, grid_size);
    defer allocator.free(host_output_grid);

    @memcpy(host_input_grid[0..grid_size], initial_state.grid[0..grid_size]);
    allocator.free(initial_state.grid);

    var event: sdl.c.SDL_Event = undefined;
    var running = true;
    while (running) {
        {
            try input_buffer.write(@ptrCast(host_input_grid.ptr), command_queue);

            try kernel_call.call();

            try output_buffer.read(@ptrCast(host_output_grid.ptr), command_queue);

            _ = cl.c.clFlush(command_queue.queue);
            _ = cl.c.clFinish(command_queue.queue);

            @memcpy(host_input_grid[0..grid_size], host_output_grid[0..grid_size]);
        }

        {
            while (sdl.c.SDL_PollEvent(&event)) {
                if (event.type == sdl.c.SDL_EVENT_QUIT) {
                    running = false;
                }
            }

            _ = sdl.c.SDL_Delay(160);

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
                    if (host_input_grid[index]) {
                        const rect = sdl.c.SDL_FRect{
                            .x = @as(f32, @floatFromInt(col)) * cell_width + padding,
                            .y = @as(f32, @floatFromInt(row)) * cell_height + padding,
                            .w = cell_width - 2 * padding,
                            .h = cell_height - 2 * padding,
                        };
                        _ = sdl.c.SDL_RenderFillRect(renderer, &rect);
                    }
                }
            }

            _ = sdl.c.SDL_RenderPresent(renderer);
        }
    }
}

fn load_initial_state(allocator: std.mem.Allocator, path: []const u8) !struct {
    width: u32,
    height: u32,
    grid: []bool,
} {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    var lines = std.mem.tokenizeAny(u8, content, "\r\n");

    const dims_line = lines.next() orelse return error.InvalidFormat;
    var dims_iter = std.mem.tokenizeScalar(u8, dims_line, ' ');
    const width_str = dims_iter.next() orelse return error.InvalidFormat;
    const height_str = dims_iter.next() orelse return error.InvalidFormat;

    const n_cols = try std.fmt.parseInt(u32, width_str, 10);
    const n_rows = try std.fmt.parseInt(u32, height_str, 10);
    const size = n_cols * n_rows;

    var grid = try allocator.alloc(bool, size);

    var row: u32 = 0;
    while (lines.next()) |line| {
        if (row >= n_rows) break;
        if (line.len < n_cols) return error.InvalidGridRow;

        for (0..n_cols) |col| {
            const c = line[col];
            grid[row * n_cols + col] = c == '1';
        }

        row += 1;
    }

    if (row != n_rows) return error.MissingGridRows;

    return .{ .width = n_cols, .height = n_rows, .grid = grid };
}
