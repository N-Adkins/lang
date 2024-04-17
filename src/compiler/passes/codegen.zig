const std = @import("std");
const ast = @import("../ast.zig");
const byte = @import("../../runtime/bytecode.zig");
const err = @import("../error.zig");
const value = @import("../../runtime/value.zig");

pub const GenError = error{
    ConstantOverflow,
} || std.mem.Allocator.Error;

pub const CodeGenPass = struct {
    bytecode: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
    constants: std.ArrayListUnmanaged(value.Value) = std.ArrayListUnmanaged(value.Value){},
    index: usize = 0,
    root: *ast.AstNode,
    err_ctx: *err.ErrorContext,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, root: *ast.AstNode) CodeGenPass {
        return CodeGenPass{
            .root = root,
            .err_ctx = err_ctx,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CodeGenPass) void {
        self.bytecode.deinit(self.allocator);
    }

    pub fn run(self: *CodeGenPass) GenError!void {
        try self.genNode(self.root);
    }

    fn genNode(self: *CodeGenPass, node: *ast.AstNode) GenError!void {
        switch (node.data) {
            .integer_constant => |int_constant| {
                try self.pushConstant(value.Value{ .data = .{ .number = int_constant.value } });
            },
            .block => |block| {
                for (block.list.items) |statement| {
                    try self.genNode(statement);
                }
            },
            else => unreachable,
        }
    }

    fn pushByte(self: *CodeGenPass, item: u8) GenError!void {
        try self.bytecode.append(self.allocator, item);
    }

    fn pushOp(self: *CodeGenPass, op: byte.Opcode) GenError!void {
        try self.bytecode.append(self.allocator, @intFromEnum(op));
    }

    fn pushConstant(self: *CodeGenPass, item: value.Value) GenError!void {
        if (self.constants.items.len >= 0xFF) {
            try self.err_ctx.newError(.constant_overflow, "Number of constants exceeds 0xFF", .{}, null);
            return GenError.ConstantOverflow;
        }
        try self.constants.append(self.allocator, item);
    }
};
