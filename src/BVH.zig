const std = @import("std");

const rtw = @import("root.zig");
const Hittable = @import("Hittable.zig");
const Interval = @import("Interval.zig");
const AABB = @import("AABB.zig");

const BVH = @This();

left: Hittable,
right: Hittable,
bbox: AABB,

pub const InitError = error{} || std.mem.Allocator.Error;

pub fn initFromSlice(
    gpa: std.mem.Allocator,
    rnd: std.Random,
    slice: []Hittable,
    start: usize,
    end: usize,
) InitError!BVH {
    const objects = try gpa.dupe(Hittable, slice);
    defer gpa.free(objects);

    const object_span = end - start;

    const left: Hittable, const right: Hittable =
        switch (object_span) {
            1 => .{ objects[start], objects[start] },
            2 => .{ objects[start], objects[start + 1] },

            else => sides: {
                std.sort.heap(
                    Hittable,
                    objects[start..end],
                    rnd.intRangeAtMost(usize, 0, 2),
                    struct {
                        fn boxCompare(axis: usize, a: Hittable, b: Hittable) bool {
                            const a_axis_interval = a.boundingBox().axisInterval(axis);
                            const b_axis_interval = b.boundingBox().axisInterval(axis);
                            return a_axis_interval.min < b_axis_interval.min;
                        }
                    }.boxCompare,
                );

                const mid = start + object_span / 2;
                break :sides .{
                    try createFromSlice(gpa, rnd, objects, start, mid),
                    try createFromSlice(gpa, rnd, objects, mid, end),
                };
            },
        };

    return .{
        .left = left,
        .right = right,
        .bbox = .fromBoxes(left.boundingBox(), right.boundingBox()),
    };
}

pub fn createFromSlice(
    gpa: std.mem.Allocator,
    rnd: std.Random,
    slice: []Hittable,
    start: usize,
    end: usize,
) !Hittable {
    const node = try gpa.create(BVH);
    node.* = try .initFromSlice(gpa, rnd, slice, start, end);
    return node.hittable();
}

pub fn init(
    gpa: std.mem.Allocator,
    rnd: std.Random,
    list: *const Hittable.List,
) BVH {
    const items = list.objects.items;
    return .initSlice(gpa, rnd, items, 0, items.len);
}

pub fn create(
    gpa: std.mem.Allocator,
    rnd: std.Random,
    list: *const Hittable.List,
) !Hittable {
    const items = list.objects.items;
    return createFromSlice(gpa, rnd, items, 0, items.len);
}

fn hit(ptr: *const anyopaque, r: rtw.Ray, ray_t: rtw.Interval) ?Hittable.Record {
    const self: *const BVH = @ptrCast(@alignCast(ptr));

    if (!self.bbox.hit(r, ray_t)) return null;

    const left_hit = self.left.hit(r, ray_t);

    var right_interval = ray_t;
    if (left_hit) |lh| right_interval.max = lh.t;

    const right_hit = self.right.hit(r, right_interval);

    // I hate that this works and I don't know how to simplify it
    if (left_hit) |lh| {
        if (right_hit) |rh| {
            return if (rh.t < lh.t) rh else lh;
        } else return lh;
    } else return right_hit;
}

fn boundingBox(ptr: *const anyopaque) AABB {
    return @as(*const BVH, @ptrCast(@alignCast(ptr))).bbox;
}

pub fn hittable(self: *BVH) Hittable {
    return .{
        .ptr = self,
        .vtable = .{
            .hit = hit,
            .boundingBox = boundingBox,
        },
    };
}
