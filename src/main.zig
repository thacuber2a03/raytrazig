const std = @import("std");

const rtw = @import("raytracing");
const vec = rtw.vec;
const Sphere = rtw.Hittable.Sphere;
const Lambertian = rtw.Material.Lambertian;
const Metal = rtw.Material.Metal;
const Dielectric = rtw.Material.Dielectric;

const help_message =
    \\usage:
    \\- raytracing [-c <n>] [-o <path>]
    \\- raytracing -h
;

fn helpAndStop(
    io: std.Io,
    comptime fmt: []const u8,
    args: anytype,
    comptime code: u8,
) !void {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    try stderr.print(fmt, args);
    try stderr.print("\n{s}\n", .{help_message});
    try stderr.flush();
    std.process.exit(code);
}

fn die(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    return helpAndStop(io, fmt, args, 64);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    var cores_amt: ?usize = null;
    var output_file: ?[]const u8 = null;

    var args_it = try init.minimal.args.iterateAllocator(arena);
    _ = args_it.next(); // exename, should print it, will deal with it later
    while (args_it.next()) |a| {
        if (a[0] == '-')
            try switch (a[1]) {
                'c' => {
                    const err = "expected number after -c";
                    if (args_it.next()) |c| {
                        cores_amt = std.fmt.parseInt(usize, c, 10) catch |e| switch (e) {
                            error.InvalidCharacter => return die(io, err, .{}),
                            else => return e,
                        };
                        if (cores_amt == 0) return die(io, "invalid number of cores", .{});
                    } else return die(io, err, .{});
                },

                'o' => if (args_it.next()) |o| {
                    output_file = o;
                } else die(io, "expected filepath after '-o'", .{}),

                'h' => helpAndStop(io, "", .{}, 0),

                else => |c| die(io, "unknown flag '{c}'", .{c}),
            }
        else
            return die(io, "unknown argument {s}", .{a});
    }

    // we abusing the init arena with this one 🗣️🔥🔥🔥🔥🔥🔥
    const demo = try createDemoScene(arena, io);

    var cam: rtw.Camera = .init(.{
        .aspect_ratio = 16.0 / 9.0,
        .image_width = 400,
        .samples_per_pixel = 100,
        .max_depth = 50,

        .vfov = 20,
        .lookfrom = .{ 13, 2, 3 },
        .lookat = vec.zero,
        .vup = .{ 0, 1, 0 },

        .defocus_angle = 0.6,
        .focus_dist = 10.0,
    });

    try cam.render(init.gpa, init.io, demo, .{
        .cores_amt = cores_amt,
        .output_file = if (output_file) |o| .{ .path = o } else .stdout,
    });
}

pub fn createDemoScene(arena: std.mem.Allocator, io: std.Io) !rtw.Hittable {
    var seed: [@sizeOf(u64)]u8 = undefined;
    io.random(&seed);
    var prng = std.Random.DefaultPrng.init(@bitCast(seed));
    const rnd = prng.random();

    var world = try arena.create(rtw.Hittable.List);
    world.* = .init;

    const ground_material: rtw.Material = try Lambertian.create(arena, .{ 0.5, 0.5, 0.5 });
    try world.objects.append(arena, try Sphere.create(arena, .{ 0, -1000, 0 }, 1000, ground_material));

    for (0..22) |i| {
        const a = @as(rtw.Real, @floatFromInt(i)) - 11;
        for (0..22) |j| {
            const b = @as(rtw.Real, @floatFromInt(j)) - 11;

            const choose_mat = rnd.float(rtw.Real);
            const center: rtw.Point3 = .{
                a + 0.9 * rnd.float(rtw.Real),
                0.2,
                b + 0.9 * rnd.float(rtw.Real),
            };

            if (vec.length(center - rtw.Point3{ 4, 0.2, 0 }) > 0.9) {
                try world.objects.append(arena, res: {
                    if (choose_mat < 0.8) {
                        const mat = try Lambertian.create(arena, vec.random(rnd) * vec.random(rnd));
                        // const center2 = center + rtw.Vec3{ 0, rtw.randomRange(rnd, 0, 0.5), 0 };
                        break :res try Sphere.create(arena, center, 0.2, mat);
                    } else {
                        const mat = try if (choose_mat < 0.95)
                            Metal.create(arena, vec.randomRange(rnd, 0.5, 1), rtw.randomRange(rnd, 0, 0.5))
                        else
                            Dielectric.create(arena, 1.5);

                        break :res try Sphere.create(arena, center, 0.2, mat);
                    }
                });
            }
        }
    }

    try world.objects.append(arena, try Sphere.create(
        arena,
        .{ 0, 1, 0 },
        1,
        try Dielectric.create(arena, 1.5),
    ));

    try world.objects.append(arena, try Sphere.create(
        arena,
        .{ -4, 1, 0 },
        1,
        try Lambertian.create(arena, .{ 0.4, 0.2, 0.1 }),
    ));

    try world.objects.append(arena, try Sphere.create(
        arena,
        .{ 4, 1, 0 },
        1,
        try Metal.create(arena, .{ 0.7, 0.6, 0.5 }, 0),
    ));

    world.updateBoundingBox();
    return rtw.BVH.create(arena, rnd, world);
}
