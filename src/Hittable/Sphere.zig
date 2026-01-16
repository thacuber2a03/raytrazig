const std = @import("std");

const AABB = @import("../AABB.zig");
const Hittable = @import("../Hittable.zig");
const Material = @import("../Material.zig");
const rtw = @import("../root.zig");
const vec = rtw.vec;

const Sphere = @This();

center: rtw.Ray,
radius: rtw.Real,
mat: Material,
bbox: AABB,

pub fn create(
    gpa: std.mem.Allocator,
    static_center: rtw.Point3,
    radius: rtw.Real,
    mat: Material,
) !Hittable {
    const sphere = try gpa.create(Sphere);
    sphere.* = .init(static_center, radius, mat);
    return sphere.hittable();
}

pub fn createMoving(
    gpa: std.mem.Allocator,
    center1: rtw.Point3,
    center2: rtw.Point3,
    radius: rtw.Real,
    mat: Material,
) !Hittable {
    const sphere = try gpa.create(Sphere);
    sphere.* = .initMoving(center1, center2, radius, mat);
    return sphere.hittable();
}

fn hit(ptr: *const anyopaque, r: rtw.Ray, ray_t: rtw.Interval) ?Hittable.Record {
    const self: *const Sphere = @ptrCast(@alignCast(ptr));

    const current_center = self.center.at(r.time);
    const oc = current_center - r.origin;
    const a = vec.lengthSquared(r.direction);
    const h = vec.dot(r.direction, oc);
    const c = vec.lengthSquared(oc) - self.radius * self.radius;

    const discriminant = h * h - a * c;
    if (discriminant < 0) return null;

    const sqrtd = std.math.sqrt(discriminant);

    var root = (h - sqrtd) / a;
    if (!ray_t.surrounds(root)) {
        root = (h + sqrtd) / a;
        if (!ray_t.surrounds(root)) return null;
    }

    var rec: Hittable.Record = undefined;
    const p = r.at(root);
    const outward_normal = vec.div(p - current_center, self.radius);
    rec.t = root;
    rec.p = p;
    rec.setFaceNormal(r, outward_normal);
    rec.mat = self.mat;
    return rec;
}

pub fn boundingBox(self: *const anyopaque) AABB {
    return @as(*const Sphere, @ptrCast(@alignCast(self))).bbox;
}

pub fn hittable(self: *Sphere) Hittable {
    return .{
        .ptr = self,
        .vtable = .{
            .hit = hit,
            .boundingBox = boundingBox,
        },
    };
}

pub fn init(static_center: rtw.Point3, radius: rtw.Real, mat: Material) Sphere {
    const rvec: rtw.Vec3 = .{ radius, radius, radius };
    return .{
        .center = .init(static_center, vec.zero),
        .radius = @max(0, radius),
        .mat = mat,
        .bbox = .fromPoints(static_center - rvec, static_center + rvec),
    };
}

pub fn initMoving(
    center1: rtw.Point3,
    center2: rtw.Point3,
    radius: rtw.Real,
    mat: Material,
) Sphere {
    const center: rtw.Ray = .init(center1, center2 - center1);
    const rvec: rtw.Vec3 = .{ radius, radius, radius };

    return .{
        .center = center,
        .radius = @max(0, radius),
        .mat = mat,
        .bbox = .fromBoxes(
            .fromPoints(center.at(0) - rvec, center.at(0) + rvec),
            .fromPoints(center.at(1) - rvec, center.at(1) + rvec),
        ),
    };
}
