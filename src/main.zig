const std = @import("std");
const log = std.log;

const cl = @import("cl.zig");
const sdl = @import("sdl3.zig");

pub fn main() cl.CLError!void {
    const device = try cl.cl_get_device();

    const ctx = cl.c.clCreateContext(null, 1, &device, null, null, null);
    if (ctx == null) {
        log.err("Failed to create OpenCL context", .{});
        return;
    }
    defer _ = cl.c.clReleaseContext(ctx);

    const command_queue = cl.c.clCreateCommandQueue(ctx, device, 0, null);
    if (command_queue == null) {
        log.err("Failed to create OpenCL command queue", .{});
        return;
    }
    defer _ = {
        _ = cl.c.clFlush(command_queue);
        _ = cl.c.clFinish(command_queue);
        _ = cl.c.clReleaseCommandQueue(command_queue);
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

    var event: sdl.c.SDL_Event = undefined;
    var running = true;
    while (running) {
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
