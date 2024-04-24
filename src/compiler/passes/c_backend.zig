//! UNUSABLE - work in progress

const std = @import("std");
const ast = @import("../ast.zig");
const byte = @import("../../runtime/bytecode.zig");
const err = @import("../error.zig");
const value = @import("../../runtime/value.zig");

pub const Error = error{
    ConstantOverflow,
    LocalOverflow,
} || std.mem.Allocator.Error;

const header_code = @embedFile("c_backend/header.c");

const Function = struct {
    root: bool = false,
    raw: []const u8,
};

pub const Pass = struct {
    allocator: std.mem.Allocator,
    functions: std.ArrayListUnmanaged(Function) = std.ArrayListUnmanaged(Function){},

    pub fn init(allocator: std.mem.Allocator) void {
        return Pass{
            .allocator = allocator,
        };
    } 
};
