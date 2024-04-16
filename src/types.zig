const std = @import("std");

pub const Type = union(enum) {
    void,
    number,

    pub fn deinit(self: *Type, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }

    pub fn equal(self: *const Type, other: *const Type) bool {
        // Update once function signature is added
        return @intFromEnum(self.*) == @intFromEnum(other.*);
    }
};

pub const builtin_lookup = std.ComptimeStringMap(Type, .{
    .{ "number", Type.number },
    .{ "void", Type.void },
});
