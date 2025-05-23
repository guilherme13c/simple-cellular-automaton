const std = @import("std");
const log = std.log;

const cl = @import("cl.zig");
const sdl = @import("sdl3.zig");

const window_width: i32 = 1000;
const window_height: i32 = 1000;

const padding: f32 = 0;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const cliArgs = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, cliArgs);

    if (cliArgs.len < 2) {
        std.log.err("Usage: {s} <path-to-initial-state>", .{cliArgs[0]});
        return;
    }

    const initial_state_path = cliArgs[1];

    const initial_state = try load_initial_state(allocator, initial_state_path);

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
    var clArgs: [4]ArgType = .{
        ArgType{ .buffer = input_buffer },
        ArgType{ .buffer = output_buffer },
        ArgType{ .uint = width },
        ArgType{ .uint = height },
    };

    const local_work_size: usize = 64;
    const remainder = grid_size % local_work_size;
    const global_work_size = if (remainder == 0) grid_size else (grid_size + (local_work_size - remainder));

    const kernel_call = cl.CLKernelCall{
        .args = @ptrCast(&clArgs),
        .kernel = kernel,
        .queue = command_queue,
        .work_dim = 1,
        .global_work_size = .{ global_work_size, 0, 0 },
        .local_work_size = .{ local_work_size, 0, 0 },
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

    var host_input_grid: []u32 = try allocator.alloc(u32, grid_size);
    defer allocator.free(host_input_grid);

    var host_output_grid: []u32 = try allocator.alloc(u32, grid_size);
    defer allocator.free(host_output_grid);

    @memcpy(host_input_grid[0..grid_size], initial_state.grid[0..grid_size]);
    allocator.free(initial_state.grid);

    var event: sdl.c.SDL_Event = undefined;
    var running = true;
    var paused = false;
    var mouse_down = false;
    while (running) {
        {
            while (sdl.c.SDL_PollEvent(&event)) {
                switch (event.type) {
                    sdl.c.SDL_EVENT_QUIT => running = false,
                    sdl.c.SDL_EVENT_KEY_DOWN => {
                        switch (event.key.key) {
                            sdl.c.SDLK_SPACE => {
                                paused = !paused;
                            },
                            sdl.c.SDLK_BACKSPACE => {
                                @memset(host_input_grid, 0);
                                @memset(host_output_grid, 0);
                            },
                            else => {},
                        }
                    },
                    sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                        mouse_down = true;
                        toggleCell(event.button.x, event.button.y, host_input_grid, width, height, cell_width, cell_height);
                    },
                    sdl.c.SDL_EVENT_MOUSE_BUTTON_UP => {
                        mouse_down = false;
                    },
                    sdl.c.SDL_EVENT_MOUSE_MOTION => {
                        if (mouse_down) {
                            toggleCell(event.motion.x, event.motion.y, host_input_grid, width, height, cell_width, cell_height);
                        }
                    },
                    else => {},
                }
            }

            _ = sdl.c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
            _ = sdl.c.SDL_RenderClear(renderer);

            _ = sdl.c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);

            for (0..height) |row| {
                for (0..width) |col| {
                    const index = row * width + col;
                    if (host_input_grid[index] == 1) {
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

        if (!paused) {
            try input_buffer.write(@ptrCast(host_input_grid.ptr), command_queue);

            try kernel_call.call();

            try output_buffer.read(@ptrCast(host_output_grid.ptr), command_queue);

            _ = cl.c.clFlush(command_queue.queue);
            _ = cl.c.clFinish(command_queue.queue);

            @memcpy(host_input_grid[0..grid_size], host_output_grid[0..grid_size]);
        }
    }
}

fn load_initial_state(allocator: std.mem.Allocator, path: []const u8) !struct {
    width: u32,
    height: u32,
    grid: []u32,
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

    var grid = try allocator.alloc(u32, size);

    var row: u32 = 0;
    while (lines.next()) |line| {
        if (row >= n_rows) break;
        if (line.len < n_cols) return error.InvalidGridRow;

        for (0..n_cols) |col| {
            const c = line[col];
            grid[row * n_cols + col] = if (c == '1') 1 else 0;
        }

        row += 1;
    }

    if (row != n_rows) return error.MissingGridRows;

    return .{ .width = n_cols, .height = n_rows, .grid = grid };
}
fn toggleCell(x: f32, y: f32, grid: []u32, width: u32, height: u32, cell_width: f32, cell_height: f32) void {
    const col: u32 = @intFromFloat(x / cell_width);
    const row: u32 = @intFromFloat(y / cell_height);

    if (col < width and row < height) {
        const idx = row * width + col;
        grid[idx] = if (grid[idx] == 1) 0 else 1;
    }
}
