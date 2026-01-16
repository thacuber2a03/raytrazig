const std = @import("std");

const rtw = @import("raytracing");
const vec = rtw.vec;
const Sphere = rtw.Hittable.Sphere;
const Lambertian = rtw.Material.Lambertian;
const Metal = rtw.Material.Metal;
const Dielectric = rtw.Material.Dielectric;
const Checker = rtw.Texture.Checker;
const RenderOptions = rtw.Camera.RenderOptions;
const InitOptions = rtw.Camera.InitOptions;

const help_message =
    \\usage: raytracing -h | [-c <n>] [-o <path>] [-r] [demo index]
    \\
    \\    -h           - show this help message
    \\
    \\    -c <n>       - set number of cores to render with, default: `cpu_count / 3 * 4`
    \\    -o <path>    - specify output path, default: outputs to stdout
    \\
    \\    -r           - "release mode";
    \\                   1200x675 px, 500 samples per pixel
    \\
    \\    [demo index] - what demo to render, defaults to 1
    \\
    \\demos:
    \\1 - book demo render + checkered floor
    \\2 - two checkered spheres
;

const max_demo_amount = 2;

fn helpAndStop(
    io: std.Io,
    comptime fmt: []const u8,
    args: anytype,
    comptime code: u8,
) !void {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    if (code != 0) try stderr.writeAll("error: ");
    try stderr.print(fmt, args);
    try stderr.writeByte('\n');
    if (fmt.len != 0) try stderr.writeByte('\n');
    try stderr.print("{s}\n", .{help_message});
    try stderr.flush();
    std.process.exit(code);
}

inline fn die(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    return helpAndStop(io, fmt, args, 64);
}

const DemoContext = struct {
    arena: *std.heap.ArenaAllocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    rnd: std.Random,
    release_mode: bool,
    render_opts: RenderOptions,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    var render_opts: RenderOptions = .{
        .cores_amt = null,
        .output_file = null,
    };

    var demo: usize = 1;
    var release_mode = false;

    var args_it = try init.minimal.args.iterateAllocator(arena);

    _ = args_it.next(); // exename, should print it, will deal with it later

    while (args_it.next()) |a| {
        if (a[0] == '-') {
            switch (a[1]) {
                'c' => {
                    const err = "expected number after -c";
                    if (args_it.next()) |c| {
                        const cores = std.fmt.parseInt(usize, c, 10) catch |e| switch (e) {
                            error.InvalidCharacter => return die(io, err, .{}),
                            else => return e,
                        };

                        if (cores == 0 or cores > try std.Thread.getCpuCount())
                            try die(io, "invalid number of cores", .{});

                        render_opts.cores_amt = cores;
                    } else try die(io, err, .{});
                },

                'o' => if (args_it.next()) |o| {
                    render_opts.output_file = o;
                } else try die(io, "expected filepath after '-o'", .{}),

                'h' => try helpAndStop(io, "", .{}, 0),

                'r' => release_mode = true,

                else => |c| try die(io, "unknown flag '{c}'", .{c}),
            }
        } else {
            demo = std.fmt.parseInt(usize, a, 10) catch |e| switch (e) {
                error.InvalidCharacter => return die(io, "unexpected argument '{s}'", .{a}),
                else => return e,
            };
            if (demo == 0 or demo > max_demo_amount) try die(io, "invalid demo index {}", .{demo});
        }
    }

    var seed: [@sizeOf(u64)]u8 = undefined;
    io.random(&seed);
    var prng = std.Random.DefaultPrng.init(@bitCast(seed));
    const rnd = prng.random();

    const demo_ctx: DemoContext = .{
        .arena = init.arena,
        .gpa = init.gpa,
        .io = init.io,
        .release_mode = release_mode,
        .render_opts = render_opts,
        .rnd = rnd,
    };

    // we abusing the init arena with this one 🗣️🔥🔥🔥🔥🔥🔥
    try switch (demo) {
        1 => renderBouncingBallsDemo(demo_ctx),
        2 => renderCheckeredSpheresDemo(demo_ctx),
        else => unreachable,
    };
}

pub fn renderBouncingBallsDemo(ctx: DemoContext) !void {
    const arena = ctx.arena.allocator();
    const rnd = ctx.rnd;

    var world = try arena.create(rtw.Hittable.List);
    world.* = .init;

    const ground_material: rtw.Material = try Lambertian.create(
        arena,
        try Checker.createColored(arena, 0.32, .{ 0.2, 0.3, 0.1 }, .{ 0.9, 0.9, 0.9 }),
    );

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
                        const mat = try Lambertian.createFromColor(arena, vec.random(rnd) * vec.random(rnd));
                        const center2 = center + rtw.Vec3{ 0, rtw.randomRange(rnd, 0, 0.5), 0 };
                        break :res try Sphere.createMoving(arena, center, center2, 0.2, mat);
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
        try Lambertian.createFromColor(arena, .{ 0.4, 0.2, 0.1 }),
    ));

    try world.objects.append(arena, try Sphere.create(
        arena,
        .{ 4, 1, 0 },
        1,
        try Metal.create(arena, .{ 0.7, 0.6, 0.5 }, 0),
    ));

    world.updateBoundingBox();

    try render(.{
        .gpa = ctx.gpa,
        .io = ctx.io,
        .world = try rtw.BVH.create(arena, world),
        .init_opts = .{
            .aspect_ratio = 16.0 / 9.0,
            .image_width = if (ctx.release_mode) 1200 else 400,
            .samples_per_pixel = if (ctx.release_mode) 500 else 10,
            .max_depth = 50,

            .vfov = 20,
            .lookfrom = .{ 13, 2, 3 },
            .lookat = vec.zero,
            .vup = .{ 0, 1, 0 },

            .defocus_angle = 0.6,
            .focus_dist = 10.0,
        },
        .render_opts = ctx.render_opts,
    });
}

pub fn renderCheckeredSpheresDemo(ctx: DemoContext) !void {
    const arena = ctx.arena.allocator();

    var world: rtw.Hittable.List = .init;

    const checker = try Checker.createColored(
        arena,
        0.32,
        .{ 0.2, 0.3, 0.1 },
        .{ 0.9, 0.9, 0.9 },
    );

    try world.objects.append(arena, try Sphere.create(
        arena,
        .{ 0, -10, 0 },
        10,
        try Lambertian.create(arena, checker),
    ));

    try world.objects.append(arena, try Sphere.create(
        arena,
        .{ 0, 10, 0 },
        10,
        try Lambertian.create(arena, checker),
    ));

    world.updateBoundingBox();
    try render(.{
        .gpa = ctx.gpa,
        .io = ctx.io,
        .world = world.hittable(),
        .init_opts = .{
            .aspect_ratio = 16.0 / 9.0,
            .image_width = if (ctx.release_mode) 1200 else 400,
            .samples_per_pixel = if (ctx.release_mode) 500 else 10,
            .max_depth = 50,

            .vfov = 20,
            .lookfrom = .{ 13, 2, 3 },
            .lookat = .{ 0, 0, 0 },
            .vup = .{ 0, 1, 0 },

            .defocus_angle = 0,
        },
        .render_opts = ctx.render_opts,
    });
}

const RenderContext = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    world: rtw.Hittable,
    init_opts: InitOptions,
    render_opts: RenderOptions,
};

pub fn render(ctx: RenderContext) !void {
    var cam: rtw.Camera = .init(ctx.init_opts);
    try cam.render(ctx.gpa, ctx.io, ctx.world, ctx.render_opts);
}
