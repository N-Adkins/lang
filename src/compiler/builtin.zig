const std = @import("std");
const types = @import("types.zig");

const void_type: types.Type = .void;

pub const Data = struct {
    id: u8,
    arg_count: usize,
    arg_types: ?[]const []const types.Type, // null if any are fine
    deep_check_types: bool = true,
    ret_type: types.Type,
};

pub const lookup = std.ComptimeStringMap(Data, .{
    .{ "print", .{
        .id = 0,
        .arg_count = 1,
        .arg_types = null,
        .ret_type = .void,
    } },
    .{ "to_string", .{
        .id = 1,
        .arg_count = 1,
        .arg_types = null,
        .ret_type = .string,
    } },
    .{ "length", .{
        .id = 2,
        .arg_count = 1,
        .arg_types = &.{&.{
            types.Type{ .array = .{ .base = @constCast(&void_type) } },
            .string,
        }},
        .deep_check_types = false,
        .ret_type = .int,
    } },
});
