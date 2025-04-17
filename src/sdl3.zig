const std = @import("std");
const info = std.log.info;

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
});
