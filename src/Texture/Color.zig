const std = @import("std");

const rtw = @import("../root.zig");
const Texture = @import("../Texture.zig");

const Color = @This();

albedo: rtw.Color,

pub fn init(albedo: rtw.Color) Color {
    return .{ .albedo = albedo };
}

pub fn create(gpa: std.mem.Allocator, albedo: rtw.Color) !Texture {
    const tex = try gpa.create(Color);
    tex.* = .init(albedo);
    return tex.texture();
}

fn value(ptr: *const anyopaque, u: rtw.Real, v: rtw.Real, p: rtw.Point3) rtw.Color {
    // ironic
    _ = u;
    _ = v;
    _ = p;

    return @as(*const Color, @ptrCast(@alignCast(ptr))).albedo;
}

pub fn texture(c: *Color) Texture {
    return .{ .ptr = c, .vtable = .{ .value = value } };
}
