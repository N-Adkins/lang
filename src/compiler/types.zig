const std = @import("std");

pub const Type = union(enum) {
    void,
    number,
    function: struct { args: std.ArrayListUnmanaged(Type), ret: *Type },

    pub fn deinit(self: *Type, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .function => |*func| {
                for (func.args.items) |*arg| {
                    arg.deinit(allocator);
                }
                func.args.deinit(allocator);
                func.ret.deinit(allocator);
            },
            else => {},
        }
    }

    pub fn equal(self: *const Type, other: *const Type) bool {
        if (@intFromEnum(self.*) != @intFromEnum(other.*)) {
            return false;
        }

        switch (self.*) {
            .function => |self_func| {
                const other_func = other.function;
                if (self_func.args.items.len != other_func.args.items.len) {
                    return false;
                }
                if (!self_func.ret.equal(other_func.ret)) {
                    return false;
                }
                for (0..self_func.args.items.len) |i| {
                    if (!self_func.args.items[i].equal(&other_func.args.items[i])) {
                        return false;
                    }
                }
                return true;
            },
            else => return true,
        }
    }
};

/// Should probably just make these keywords
pub const builtin_lookup = std.ComptimeStringMap(Type, .{
    .{ "number", Type.number },
    .{ "void", Type.void },
});
