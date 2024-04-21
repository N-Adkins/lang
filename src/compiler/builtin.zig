const std = @import("std");
const types = @import("types.zig");

pub const Data = struct {
    arg_count: usize,
    ret_type: types.Type,
};

pub const lookup = std.ComptimeStringMap(Data, .{
    .{ "print", .{
        .arg_count = 1,
        .ret_type = .void,
    } },
    .{ "to_string", .{
        .arg_count = 1,
        .ret_type = .string,
    } },
});
