const std = @import("std");

const Hittable = @import("../Hittable.zig");
const AABB = @import("../AABB.zig");
const rtw = @import("../root.zig");
const vec = rtw.vec;

const List = @This();

/// This field is intended to be accessed and modified directly.
///
/// Make sure to call `updateBoundingBox` after a batch of object registers
/// to update the bounding box cache.
objects: std.ArrayList(Hittable) = .empty,

/// The composite bounding box cache of all objects in this list.
bbox: AABB = .empty,

pub const init: List = .{};

pub fn deinit(self: *List, gpa: std.mem.Allocator) void {
    self.objects.deinit(gpa);
}

/// Update the composite bounding box cached of this list.
// TODO: should I add this note here?
/// This method is only recommended for usage in batch object registering,
/// as it can be slow to iterate through all the items on the list.
pub fn updateBoundingBox(self: *List) void {
    for (self.objects.items) |o|
        self.bbox = .fromBoxes(self.bbox, o.boundingBox());
}

/// Append an object to the list, and immediately update the cached AABB.
///
/// It is recommended to use this method for one-off objects.
pub fn add(self: *List, gpa: std.mem.Allocator, object: Hittable) !void {
    try self.objects.append(gpa, object);
    self.bbox = .fromBoxes(self.bbox, object.boundingBox());
}

fn hit(ptr: *const anyopaque, r: rtw.Ray, ray_t: rtw.Interval) ?Hittable.Record {
    const self: *const List = @ptrCast(@alignCast(ptr));

    var rec: ?Hittable.Record = null;
    var closest_so_far = ray_t.max;

    for (self.objects.items) |o|
        if (o.hit(r, .init(ray_t.min, closest_so_far))) |res| {
            rec = res;
            closest_so_far = res.t;
        };

    return rec;
}

pub fn boundingBox(self: *const anyopaque) AABB {
    return @as(*const List, @ptrCast(@alignCast(self))).bbox;
}

pub fn hittable(self: *List) Hittable {
    return .{
        .ptr = self,
        .vtable = .{
            .hit = hit,
            .boundingBox = boundingBox,
        },
    };
}
