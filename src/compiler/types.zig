const std = @import("std");

pub const Type = union(enum) {
    void,
    int,
    boolean,
    string,
    array: struct { base: *Type },
    function: struct { args: std.ArrayListUnmanaged(Type) = std.ArrayListUnmanaged(Type){}, ret: *Type },

    pub fn equal(self: *const Type, other: *const Type) bool {
        if (@intFromEnum(self.*) != @intFromEnum(other.*)) {
            return false;
        }

        switch (self.*) {
            .array => |base| {
                switch (other.*) {
                    .array => |other_base| return base.base.equal(other_base.base),
                    else => return false,
                }
            },
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

    pub fn format(self: Type, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .void => try writer.writeAll("void"),
            .boolean => try writer.writeAll("bool"),
            .int => try writer.writeAll("int"),
            .string => try writer.writeAll("string"),
            .array => |base| try writer.print("[{any}]", base),
            .function => |func| {
                try writer.writeAll("fn (");
                for (0..func.args.items.len) |i| {
                    try writer.print("{any}", .{func.args.items[i]});
                    if (i < func.args.items.len - 1) {
                        try writer.writeAll(", ");
                    }
                }
                try writer.print(") -> {any}", .{func.ret});
            },
        }
    }
};

/// Should probably just make these keywords
pub const builtin_lookup = std.StaticStringMap(Type).initComptime(.{
    .{ "int", Type.int },
    .{ "bool", Type.boolean },
    .{ "string", Type.string },
    .{ "void", Type.void },
});
