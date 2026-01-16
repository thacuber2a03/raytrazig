const std = @import("std");

const rtw = @import("../root.zig");
const Texture = @import("../Texture.zig");
const Color = @import("Color.zig");

const Checker = @This();

inv_scale: rtw.Real,
even: Texture,
odd: Texture,

pub fn init(scale: rtw.Real, even: Texture, odd: Texture) Checker {
    return .{
        .inv_scale = 1.0 / scale,
        .even = even,
        .odd = odd,
    };
}

pub fn initColored(
    gpa: std.mem.Allocator,
    scale: rtw.Real,
    c1: rtw.Color,
    c2: rtw.Color,
) !Checker {
    return .init(scale, try Color.create(gpa, c1), try Color.create(gpa, c2));
}

pub fn create(gpa: std.mem.Allocator, scale: rtw.Real, even: Texture, odd: Texture) !Texture {
    const tex = try gpa.create(Checker);
    tex.* = .init(scale, even, odd);
    return tex.texture();
}

pub fn createColored(
    gpa: std.mem.Allocator,
    scale: rtw.Real,
    even: rtw.Color,
    odd: rtw.Color,
) !Texture {
    const tex = try gpa.create(Checker);
    tex.* = try .initColored(gpa, scale, even, odd);
    return tex.texture();
}

fn value(ptr: *const anyopaque, u: rtw.Real, v: rtw.Real, p: rtw.Point3) rtw.Color {
    const self: *const Checker = @ptrCast(@alignCast(ptr));

    const p_integer: rtw.Vector3(i64) =
        @intFromFloat(@floor(rtw.vec.scale(p, self.inv_scale)));

    const is_even = @rem(p_integer[0] + p_integer[1] + p_integer[2], 2) == 0;

    return (if (is_even) self.even else self.odd).value(u, v, p);
}

pub fn texture(c: *Checker) Texture {
    return .{ .ptr = c, .vtable = .{ .value = value } };
}
