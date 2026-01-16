const std = @import("std");
const sqrt = std.math.sqrt;

// not a type
const rtw = @This();

pub const Hittable = @import("Hittable.zig");
pub const Material = @import("Material.zig");
pub const Interval = @import("Interval.zig");
pub const Camera = @import("Camera.zig");
pub const BVH = @import("BVH.zig");

fn Vector3(T: type) type {
    return @Vector(3, T);
}

pub const Real = f64;
pub const Vec3 = Vector3(Real);
pub const Color = Vec3;
pub const Point3 = Vec3;

pub fn randomRange(rnd: std.Random, min: Real, max: Real) Real {
    return std.math.lerp(min, max, rnd.float(Real));
}

pub const vec = @import("vec.zig");

pub const color = struct {
    fn linearToGamma(linearComponent: Real) Real {
        return if (linearComponent > 0) sqrt(linearComponent) else 0;
    }

    pub fn write(out: *std.Io.Writer, pixel_color: Color) !void {
        const intensity: Interval = .init(0, 0.999);

        const transformed: Color = .{ linearToGamma(pixel_color[0]), linearToGamma(pixel_color[1]), linearToGamma(pixel_color[2]) };
        const clamped: Color = .{ intensity.clamp(transformed[0]), intensity.clamp(transformed[1]), intensity.clamp(transformed[2]) };

        const byte_color: Vector3(u8) = @intFromFloat(@trunc(vec.scale(clamped, 256)));

        try out.print("{} {} {}\n", .{ byte_color[0], byte_color[1], byte_color[2] });
    }
};

pub const Ray = struct {
    origin: Vec3,
    direction: Vec3,
    time: Real = 0,

    pub fn initAtTime(origin: Vec3, direction: Vec3, time: Real) Ray {
        return .{ .origin = origin, .direction = direction, .time = time };
    }

    pub fn init(origin: Vec3, direction: Vec3) Ray {
        return .{ .origin = origin, .direction = direction };
    }

    pub fn at(self: Ray, t: Real) Point3 {
        return self.origin + vec.scale(self.direction, t);
    }
};
