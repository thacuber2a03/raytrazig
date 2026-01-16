const std = @import("std");
const Io = std.Io;

const rtw = @import("root.zig");
const vec = rtw.vec;

const Camera = @This();

aspect_ratio: rtw.Real,
image_width: usize,
samples_per_pixel: usize,
max_depth: usize,

vfov: rtw.Real,
lookfrom: rtw.Point3,
lookat: rtw.Point3,
vup: rtw.Vec3,

defocus_angle: rtw.Real,
focus_dist: rtw.Real,

image_height: usize,
pixel_samples_scale: rtw.Real,
center: rtw.Point3,
pixel00_loc: rtw.Point3,
pixel_delta_u: rtw.Vec3,
pixel_delta_v: rtw.Vec3,
u: rtw.Vec3,
v: rtw.Vec3,
w: rtw.Vec3,
defocus_disk_u: rtw.Vec3,
defocus_disk_v: rtw.Vec3,

pub const InitOptions = struct {
    aspect_ratio: rtw.Real = 1.0,
    image_width: usize = 100,
    samples_per_pixel: usize = 10,
    max_depth: usize = 10,

    vfov: rtw.Real = 90,
    lookfrom: rtw.Point3 = vec.zero,
    lookat: rtw.Point3 = .{ 0, 0, -1 },
    vup: rtw.Vec3 = .{ 0, 1, 0 },

    defocus_angle: rtw.Real = 0,
    focus_dist: rtw.Real = 10,
};

pub fn init(opts: InitOptions) Camera {
    var cam: Camera = undefined;
    cam.aspect_ratio = opts.aspect_ratio;
    cam.image_width = opts.image_width;
    cam.samples_per_pixel = opts.samples_per_pixel;
    cam.max_depth = opts.max_depth;

    cam.vfov = opts.vfov;
    cam.lookat = opts.lookat;
    cam.lookfrom = opts.lookfrom;
    cam.vup = opts.vup;

    cam.defocus_angle = opts.defocus_angle;
    cam.focus_dist = opts.focus_dist;

    const float_image_width: rtw.Real = @floatFromInt(cam.image_width);

    cam.image_height = @intFromFloat(@max(1, float_image_width) / cam.aspect_ratio);

    // yea having it here and not next to float_image_width
    // is kinda awkward but what can you do about it :P
    const float_image_height: rtw.Real = @floatFromInt(cam.image_height);

    cam.pixel_samples_scale = 1.0 / @as(rtw.Real, @floatFromInt(cam.samples_per_pixel));

    cam.center = cam.lookfrom;

    const theta = std.math.degreesToRadians(cam.vfov);
    const h = std.math.tan(theta / 2);
    const viewport_height = 2.0 * h * cam.focus_dist;
    const viewport_width = viewport_height * float_image_width / float_image_height;

    cam.w = vec.unit(cam.lookfrom - cam.lookat);
    cam.u = vec.unit(vec.cross(cam.vup, cam.w));
    cam.v = vec.cross(cam.w, cam.u);

    const viewport_u: rtw.Vec3 = vec.scale(cam.u, viewport_width);
    const viewport_v: rtw.Vec3 = vec.scale(-cam.v, viewport_height);

    cam.pixel_delta_u = vec.div(viewport_u, float_image_width);
    cam.pixel_delta_v = vec.div(viewport_v, float_image_height);

    const viewport_upper_left =
        cam.center - vec.scale(cam.w, cam.focus_dist) -
        vec.div(viewport_u, 2) - vec.div(viewport_v, 2);

    cam.pixel00_loc = viewport_upper_left +
        vec.scale(cam.pixel_delta_u + cam.pixel_delta_v, 0.5);

    const defocus_radius = cam.focus_dist *
        std.math.tan(std.math.degreesToRadians(cam.defocus_angle / 2));
    cam.defocus_disk_u = vec.scale(cam.u, defocus_radius);
    cam.defocus_disk_v = vec.scale(cam.v, defocus_radius);

    return cam;
}

const TILE_SIZE = 32;

const RenderContext = struct {
    tile_idx: std.atomic.Value(usize),
    num_tiles_x: usize,
    total_tiles: usize,
    image_data: []rtw.Color,
};

const Worker = struct {
    context: *RenderContext,
    image_progress: *std.Progress.Node,
    tile_progress: std.Progress.Node,
    random_seed: u64,
    world: *const rtw.Hittable,

    pub fn work(self: *Worker, cam: *Camera) void {
        const ctx = self.context;
        while (true) {
            const tile_idx = ctx.tile_idx.fetchAdd(1, .monotonic);
            if (tile_idx >= ctx.total_tiles) break;
            self.tile_progress.setCompletedItems(0);

            const tx = tile_idx % ctx.num_tiles_x;
            const ty = tile_idx / ctx.num_tiles_x;

            const x_start = tx * TILE_SIZE;
            const y_start = ty * TILE_SIZE;

            const x_end = @min(x_start + TILE_SIZE, cam.image_width);
            const y_end = @min(y_start + TILE_SIZE, cam.image_height);

            self.draw(cam, x_start, y_start, x_end, y_end);

            self.image_progress.completeOne();
        }

        self.tile_progress.end();
    }

    pub fn draw(
        self: *Worker,
        cam: *Camera,
        x_start: usize,
        y_start: usize,
        x_end: usize,
        y_end: usize,
    ) void {
        var prng = std.Random.DefaultPrng.init(
            self.random_seed ^
                @as(u64, @intCast(x_start)) ^
                (@as(u64, @intCast(y_start)) << 32),
        );
        const rnd = prng.random();

        const w = cam.image_width;

        for (y_start..y_end) |y| {
            for (x_start..x_end) |x| {
                var pixel_color: rtw.Color = vec.zero;

                for (0..cam.samples_per_pixel) |_|
                    pixel_color += rayColor(
                        rnd,
                        getRay(cam, rnd, x, y),
                        cam.max_depth,
                        self.world,
                    );

                self.context.image_data[y * w + x] =
                    vec.scale(pixel_color, cam.pixel_samples_scale);

                self.tile_progress.completeOne();
            }
        }
    }

    fn rayColor(rnd: std.Random, r: rtw.Ray, depth: usize, world: *const rtw.Hittable) rtw.Color {
        if (depth <= 0) return vec.zero;

        if (world.hit(r, .init(0.001, std.math.inf(rtw.Real)))) |rec|
            return if (rec.mat.scatter(r, &rec, rnd)) |scatter_res|
                scatter_res.attenuation *
                    rayColor(rnd, scatter_res.scattered, depth - 1, world)
            else
                vec.zero;

        const unit_dir = vec.unit(r.direction);
        const a = 0.5 * (unit_dir[1] + 1.0);
        return vec.scale(.{ 1, 1, 1 }, 1 - a) + vec.scale(.{ 0.25, 0.4, 1 }, a);
    }

    fn getRay(cam: *Camera, rnd: std.Random, i: usize, j: usize) rtw.Ray {
        const offset = sampleSquare(rnd);
        const pixel_sample = cam.pixel00_loc +
            vec.scale(cam.pixel_delta_u, @as(rtw.Real, @floatFromInt(i)) + offset[0]) +
            vec.scale(cam.pixel_delta_v, @as(rtw.Real, @floatFromInt(j)) + offset[1]);

        const origin = if (cam.defocus_angle <= 0)
            cam.center
        else
            defocusDiskSample(cam, rnd);

        const direction = pixel_sample - origin;
        const time = rnd.float(rtw.Real);

        return .initAtTime(origin, direction, time);
    }

    fn sampleSquare(rnd: std.Random) rtw.Vec3 {
        return .{ rnd.float(rtw.Real) - 0.5, rnd.float(rtw.Real) - 0.5, 0 };
    }

    fn defocusDiskSample(cam: *Camera, rnd: std.Random) rtw.Point3 {
        const p = vec.randomInUnitDisk(rnd);
        return cam.center + vec.scale(cam.defocus_disk_u, p[0]) + vec.scale(cam.defocus_disk_v, p[1]);
    }
};

pub const RenderOptions = struct {
    /// If `null`, outputs to stdout.
    output_file: ?[]const u8 = "out.ppm",
    /// If `null`, defaults to `cpu_count * 3 / 4`.
    cores_amt: ?usize = null,
};

pub fn render(
    self: *Camera,
    gpa: std.mem.Allocator,
    io: Io,
    world: rtw.Hittable,
    opts: RenderOptions,
) !void {
    var root_progress = std.Progress.start(io, .{});
    defer root_progress.end();

    var rnd_buf: [@sizeOf(u64)]u8 = undefined;
    io.random(&rnd_buf);
    var prng = std.Random.DefaultPrng.init(@bitCast(rnd_buf));

    const num_tiles_x = (self.image_width + TILE_SIZE - 1) / TILE_SIZE;
    const num_tiles_y = (self.image_height + TILE_SIZE - 1) / TILE_SIZE;
    const total_tiles = num_tiles_x * num_tiles_y;

    var ctx: RenderContext = .{
        .tile_idx = .init(0),
        .num_tiles_x = num_tiles_x,
        .total_tiles = total_tiles,
        .image_data = try gpa.alloc(rtw.Color, self.image_width * self.image_height),
    };
    defer gpa.free(ctx.image_data);

    var image_progress = root_progress.start("Finished tiles", total_tiles);
    defer image_progress.end();

    const workers_count = opts.cores_amt orelse
        @min(try std.Thread.getCpuCount() * 3 / 4, self.image_height);
    if (workers_count == 0)
        std.debug.panic("attempt to render image with no cores", .{});

    const workers = try gpa.alloc(Worker, workers_count);
    defer gpa.free(workers);

    var wg = std.Thread.WaitGroup{};
    for (workers, 0..) |*w, i| {
        var progress_node_buf: [128]u8 = undefined;
        const tile_progress = image_progress.start(std.fmt.bufPrint(
            &progress_node_buf,
            "Plotted pixels (worker {})",
            .{i + 1},
        ) catch unreachable, TILE_SIZE * TILE_SIZE);

        w.* = .{
            .context = &ctx,
            .image_progress = &image_progress,
            .tile_progress = tile_progress,
            .random_seed = prng.random().int(u64),
            .world = &world,
        };

        wg.spawnManager(Worker.work, .{ w, self });
    }
    wg.wait();

    ////////////////////////////////////////////////////////////////////////////////

    var file_handle: Io.File = if (opts.output_file) |path|
        try Io.Dir.cwd().createFile(io, path, .{})
    else
        .stdout();

    defer if (opts.output_file) |_| file_handle.close(io);

    var file_buffer: [1024]u8 = undefined;
    var file_writer = file_handle.writer(io, &file_buffer);
    const file = &file_writer.interface;

    try file.print("P3\n{} {}\n255\n", .{ self.image_width, self.image_height });

    for (ctx.image_data) |c| try rtw.color.write(file, c);

    try file.flush();

    if (opts.output_file) |_| std.log.info("done, check the current directory", .{});
}
