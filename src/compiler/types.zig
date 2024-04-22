const std = @import("std");

pub const Type = union(enum) {
    void,
    number,
    boolean,
    string,
    function: struct { args: std.ArrayListUnmanaged(Type) = std.ArrayListUnmanaged(Type){}, ret: *Type },

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

    pub fn format(self: Type, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .void => try writer.writeAll("void"),
            .boolean => try writer.writeAll("bool"),
            .number => try writer.writeAll("number"),
            .string => try writer.writeAll("string"),
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
pub const builtin_lookup = std.ComptimeStringMap(Type, .{
    .{ "number", Type.number },
    .{ "bool", Type.boolean },
    .{ "string", Type.string },
    .{ "void", Type.void },
});
