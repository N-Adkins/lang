const std = @import("std");

pub const Type = union(enum) {
    number,

    pub fn deinit(self: *Type, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const builtin_lookup = std.ComptimeStringMap(Type, .{
    .{ "number", Type.number },
});
