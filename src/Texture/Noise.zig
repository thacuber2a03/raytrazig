const std = @import("std");

const rtw = @import("../root.zig");
const vec = rtw.vec;
const Texture = @import("../Texture.zig");

const Perlin = struct {
    const point_count = 256;

    // TODO: these could maybe probably be @Vectors as well
    randvec: [point_count]rtw.Vec3,
    perm_x: [point_count]usize,
    perm_y: [point_count]usize,
    perm_z: [point_count]usize,

    pub fn init(rnd: std.Random) Perlin {
        var p: Perlin = undefined;
        for (&p.randvec) |*r| r.* = vec.randomRange(rnd, -1, 1);
        generatePermute(rnd, p.perm_x[0..]);
        generatePermute(rnd, p.perm_y[0..]);
        generatePermute(rnd, p.perm_z[0..]);
        return p;
    }

    pub fn noise(self: *const Perlin, p: rtw.Point3) rtw.Real {
        const u = p[0] - std.math.floor(p[0]);
        const v = p[1] - std.math.floor(p[1]);
        const w = p[2] - std.math.floor(p[2]);

        const i: isize = @intFromFloat(std.math.floor(p[0]));
        const j: isize = @intFromFloat(std.math.floor(p[1]));
        const k: isize = @intFromFloat(std.math.floor(p[2]));

        var c: [2][2][2]rtw.Vec3 = undefined;

        for (0..2) |di|
            for (0..2) |dj| {
                for (0..2) |dk|
                    c[di][dj][dk] = self.randvec[
                        self.perm_x[@as(usize, @intCast((i + @as(isize, @intCast(di))) & 255))] ^
                            self.perm_y[@as(usize, @intCast((j + @as(isize, @intCast(dj))) & 255))] ^
                            self.perm_z[@as(usize, @intCast((k + @as(isize, @intCast(dk))) & 255))]
                    ];
            };

        return perlinInterp(&c, u, v, w);
    }

    pub fn turb(self: *const Perlin, p: rtw.Point3, depth: usize) rtw.Real {
        var accum: rtw.Real = 0;
        var temp_p = p;
        var weight: rtw.Real = 1;

        for (0..depth) |_| {
            accum += weight * self.noise(temp_p);
            weight *= 0.5;
            temp_p = vec.scale(temp_p, 2);
        }

        return @abs(accum);
    }

    fn perlinInterp(c: *const [2][2][2]rtw.Vec3, u: rtw.Real, v: rtw.Real, w: rtw.Real) rtw.Real {
        const uu = u * u * (3 - 2 * u);
        const vv = v * v * (3 - 2 * v);
        const ww = w * w * (3 - 2 * w);
        var accum: rtw.Real = 0;

        for (0..2) |i|
            for (0..2) |j| {
                for (0..2) |k| {
                    const ii: rtw.Real = @floatFromInt(i);
                    const jj: rtw.Real = @floatFromInt(j);
                    const kk: rtw.Real = @floatFromInt(k);
                    const weight_v: rtw.Vec3 = .{ u - ii, v - jj, w - kk };
                    accum +=
                        (ii * uu + (1 - ii) * (1 - uu)) *
                        (jj * vv + (1 - jj) * (1 - vv)) *
                        (kk * ww + (1 - kk) * (1 - ww)) *
                        vec.dot(c[i][j][k], weight_v);
                }
            };

        return accum;
    }

    fn generatePermute(rnd: std.Random, p: []usize) void {
        for (0..p.len) |i| p[i] = i;
        rnd.shuffle(usize, p);
    }
};

const Noise = @This();

noise: Perlin,
scale: rtw.Real,

pub fn init(rnd: std.Random, scale: rtw.Real) Noise {
    return .{ .noise = .init(rnd), .scale = scale };
}

pub fn create(gpa: std.mem.Allocator, rnd: std.Random, scale: rtw.Real) !Texture {
    const tex = try gpa.create(Noise);
    tex.* = .init(rnd, scale);
    return tex.texture();
}

fn value(ptr: *const anyopaque, u: rtw.Real, v: rtw.Real, p: rtw.Point3) rtw.Color {
    _ = u;
    _ = v;
    const self: *const Noise = @ptrCast(@alignCast(ptr));
    const turb = self.noise.turb(p, 7);
    return vec.scale(.{ 0.5, 0.5, 0.5 }, 1 + std.math.sin(self.scale * p[2] + 10 * turb));
}

pub fn texture(c: *Noise) Texture {
    return .{ .ptr = c, .vtable = .{ .value = value } };
}
