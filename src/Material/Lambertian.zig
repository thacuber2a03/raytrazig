const std = @import("std");

const rtw = @import("../root.zig");
const vec = rtw.vec;

const Material = @import("../Material.zig");
const Hittable = @import("../Hittable.zig");
const Texture = @import("../Texture.zig");
const Color = @import("../Texture/Color.zig");

const Lambertian = @This();

tex: Texture,

fn scatter(
    ptr: *anyopaque,
    r_in: rtw.Ray,
    rec: *const Hittable.Record,
    rnd: std.Random,
) ?Material.Scatter {
    const self: *const Lambertian = @ptrCast(@alignCast(ptr));
    var scatter_direction = rec.normal + vec.randomUnitVector(rnd);

    if (vec.nearZero(scatter_direction))
        scatter_direction = rec.normal;

    return .{
        .attenuation = self.tex.value(rec.u, rec.v, rec.p),
        .scattered = .initAtTime(rec.p, scatter_direction, r_in.time),
    };
}

pub fn initFromColor(gpa: std.mem.Allocator, albedo: rtw.Color) !Lambertian {
    return .{ .tex = try Color.create(gpa, albedo) };
}

pub fn createFromColor(gpa: std.mem.Allocator, albedo: rtw.Color) !Material {
    const mat = try gpa.create(Lambertian);
    mat.* = try .initFromColor(gpa, albedo);
    return mat.material();
}

pub fn init(tex: Texture) Lambertian {
    return .{ .tex = tex };
}

pub fn create(gpa: std.mem.Allocator, tex: Texture) !Material {
    const mat = try gpa.create(Lambertian);
    mat.* = .init(tex);
    return mat.material();
}

pub fn material(self: *Lambertian) Material {
    return .{ .ptr = self, .vtable = .{ .scatter = scatter } };
}
