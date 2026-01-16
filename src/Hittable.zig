pub const List = @import("Hittable/List.zig");
pub const Sphere = @import("Hittable/Sphere.zig");
const Interval = @import("Interval.zig");
const Material = @import("Material.zig");
const AABB = @import("AABB.zig");
const rtw = @import("root.zig");

pub const Record = struct {
    p: rtw.Point3,
    normal: rtw.Point3,
    mat: Material,
    t: rtw.Real,
    front_face: bool,

    pub fn setFaceNormal(self: *Record, r: rtw.Ray, outward_normal: rtw.Vec3) void {
        self.front_face = rtw.vec.dot(r.direction, outward_normal) < 0;
        self.normal = if (self.front_face) outward_normal else -outward_normal;
    }
};

const Hittable = @This();

ptr: *anyopaque,
vtable: VTable,

pub const VTable = struct {
    hit: *const fn (ptr: *const anyopaque, r: rtw.Ray, ray_t: rtw.Interval) ?Record,
    boundingBox: *const fn (ptr: *const anyopaque) AABB,
};

pub fn hit(self: Hittable, r: rtw.Ray, ray_t: rtw.Interval) ?Record {
    return self.vtable.hit(@constCast(self.ptr), r, ray_t);
}

pub fn boundingBox(self: Hittable) AABB {
    return self.vtable.boundingBox(@constCast(self.ptr));
}
