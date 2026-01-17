const std = @import("std");

const clap = @import("clap");

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
    \\usage: raytracing --help | [-c <n>] [-o <path>] [-r] [demo index]
    \\
    \\    -h, --help          - show this help message
    \\    -c, --cores <n>     - set number of cores to render with, default: `cpu_count / 3 * 4`
    \\    -o, --output <path> - specify output path, default: outputs to stdout
    \\    -r, --release       - "release mode"; 1200x675 px, 500 samples per pixel
    \\
    \\    [demo index] - what demo to render, defaults to 1
    \\
    \\demos:
    \\1 - book demo render + checkered floor
    \\2 - two checkered spheres
    \\3 - earth
;

const max_demo_amount = 4;

fn helpAndStop(
    comptime fmt: []const u8,
    args: anytype,
    comptime code: u8,
) !void {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.fs.File.Writer = .init(.stderr(), &stderr_buffer);
    const stderr = &stderr_writer.interface;

    if (fmt.len != 0) {
        if (code != 0) try stderr.writeAll("error: ");
        try stderr.print(fmt, args);
        try stderr.writeAll("\n\n");
    }

    try stderr.print("{s}\n", .{help_message});
    try stderr.flush();
    std.process.exit(code);
}

inline fn die(comptime fmt: []const u8, args: anytype) !void {
    return helpAndStop(fmt, args, 64);
}

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const gpa = debug_allocator.allocator();

    var render_opts: RenderOptions = .{
        .cores_amt = null,
        .output_file = null,
    };

    var demo: usize = 1;
    var release_mode = false;

    _ = &render_opts;
    _ = &demo;
    _ = &release_mode;

    const params = comptime clap.parseParamsComptime(
        \\ -h, --help          show this help message
        \\ -c, --cores <usize> set number of cores to render with, default: `cpu_count / 3 * 4`
        \\ -o, --output <str>  specify output path, default: outputs to stdout
        \\ -r, --release       "release mode"; 1200x675 px, 500 samples per pixel
        \\ <usize>             what demo to render, defaults to 1
    );

    var diag: clap.Diagnostic = .{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        try helpAndStop("", .{}, 0)
    else {
        if (res.args.cores) |c| {
            if (c == 0 or c > try std.Thread.getCpuCount())
                try die("invalid amount of CPU cores", .{});

            render_opts.cores_amt = c;
        }

        release_mode = res.args.release != 0;
        if (res.args.output) |o| render_opts.output_file = o;
        if (res.positionals[0]) |d| demo = d;
    }

    var prng = std.Random.DefaultPrng.init(std.crypto.random.int(u64));
    const rnd = prng.random();

    const demo_ctx: DemoContext = .{
        .arena = &arena_allocator,
        .gpa = gpa,
        .release_mode = release_mode,
        .render_opts = render_opts,
        .rnd = rnd,
    };

    // I can *not* be fucking bothered to figure out the errors here
    const demos = [_]*const fn (DemoContext) anyerror!void{
        renderBouncingBallsDemo,
        renderCheckeredSpheresDemo,
        renderEarthDemo,
        renderPerlinSpheresDemo,
    };

    try demos[demo](demo_ctx);
}

const DemoContext = struct {
    arena: *std.heap.ArenaAllocator,
    gpa: std.mem.Allocator,
    rnd: std.Random,
    release_mode: bool,
    render_opts: RenderOptions,
};

pub fn renderBouncingBallsDemo(ctx: DemoContext) !void {
    // we abusing the init arena with this one 🗣️🔥🔥🔥🔥🔥🔥
    const rnd = ctx.rnd;
    const arena = ctx.arena.allocator();

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
        .world = world.hittable(),
        .init_opts = .{
            .aspect_ratio = 16.0 / 9.0,
            .image_width = if (ctx.release_mode) 1200 else 400,
            .samples_per_pixel = if (ctx.release_mode) 500 else 10,
            .max_depth = 50,

            .vfov = 20,
            .lookfrom = .{ 13, 2, 3 },
            .lookat = vec.zero,
            .vup = .{ 0, 1, 0 },

            .defocus_angle = 0,
        },
        .render_opts = ctx.render_opts,
    });
}

pub fn renderEarthDemo(ctx: DemoContext) !void {
    var image_manager = rtw.ImageManager.init(ctx.gpa);
    defer image_manager.deinit();

    var earth_texture: rtw.Texture.Image = try .init(&image_manager, "assets/earthmap.jpg");
    var earth_surface: Lambertian = .init(earth_texture.texture());
    var globe: Sphere = .init(vec.zero, 2, earth_surface.material());

    try render(.{
        .gpa = ctx.gpa,
        .world = globe.hittable(),
        .init_opts = .{
            .aspect_ratio = 16.0 / 9.0,
            .image_width = if (ctx.release_mode) 1200 else 400,
            .samples_per_pixel = if (ctx.release_mode) 500 else 10,
            .max_depth = 50,

            .vfov = 20,
            .lookfrom = .{ 0, 0, 12 },
            .lookat = vec.zero,
            .vup = .{ 0, 1, 0 },

            .defocus_angle = 0,
        },
        .render_opts = ctx.render_opts,
    });
}

pub fn renderPerlinSpheresDemo(ctx: DemoContext) !void {
    const arena = ctx.arena.allocator();
    const rnd = ctx.rnd;

    var world: rtw.Hittable.List = .init;

    var pertext: rtw.Texture.Noise = .init(rnd, 4);
    var mat: Lambertian = .init(pertext.texture());

    try world.objects.append(arena, try Sphere.create(
        arena,
        .{ 0, -1000, 0 },
        1000,
        mat.material(),
    ));

    try world.objects.append(arena, try Sphere.create(
        arena,
        .{ 0, 2, 0 },
        2,
        mat.material(),
    ));

    world.updateBoundingBox();
    try render(.{
        .gpa = ctx.gpa,
        .world = world.hittable(),
        .init_opts = .{
            .aspect_ratio = 16.0 / 9.0,
            .image_width = if (ctx.release_mode) 1200 else 400,
            .samples_per_pixel = if (ctx.release_mode) 500 else 10,
            .max_depth = 50,

            .vfov = 20,
            .lookfrom = .{ 13, 2, 3 },
            .lookat = vec.zero,
            .vup = .{ 0, 1, 0 },

            .defocus_angle = 0,
        },
        .render_opts = ctx.render_opts,
    });
}

const RenderContext = struct {
    gpa: std.mem.Allocator,
    world: rtw.Hittable,
    init_opts: InitOptions,
    render_opts: RenderOptions,
};

pub fn render(ctx: RenderContext) !void {
    var cam: rtw.Camera = .init(ctx.init_opts);
    try cam.render(ctx.gpa, ctx.world, ctx.render_opts);
}
