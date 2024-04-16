const std = @import("std");
const byte = @import("bytecode.zig");
const stack = @import("stack.zig");
const value = @import("value.zig");

pub const VM = struct {
    bytes: []const u8,
    constants: []const value.Value,
    stack: stack.Stack,
};
