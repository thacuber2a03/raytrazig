const rtw = @import("root.zig");

pub const Color = @import("Texture/Color.zig");
pub const Checker = @import("Texture/Checker.zig");

const Texture = @This();

ptr: *anyopaque,
vtable: VTable,

pub const VTable = struct {
    value: *const fn (ptr: *const anyopaque, u: rtw.Real, v: rtw.Real, p: rtw.Point3) rtw.Color,
};

pub fn value(self: Texture, u: rtw.Real, v: rtw.Real, p: rtw.Point3) rtw.Color {
    return self.vtable.value(self.ptr, u, v, p);
}
