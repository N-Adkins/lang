const std = @import("std");
const ast = @import("../ast.zig");
const err = @import("../error.zig");
const types = @import("../types.zig");

pub const Error = error{
    MismatchedTypes,
} || std.mem.Allocator.Error;

pub const Pass = struct {
    root: *ast.Node,
    err_ctx: *err.ErrorContext,

    pub fn init(err_ctx: *err.ErrorContext, root: *ast.Node) Pass {
        return Pass{
            .root = root,
            .err_ctx = err_ctx,
        };
    }

    pub fn run(self: *Pass) Error!void {
        _ = try self.typeCheck(self.root);
    }

    fn typeCheck(self: *Pass, node: *ast.Node) Error!types.Type {
        switch (node.data) {
            .integer_constant => return .number,
            .var_get => |_| return node.symbol_decl.?.*.data.var_decl.decl_type,
            .block => |block| {
                for (block.list.items) |statement| {
                    _ = try self.typeCheck(statement);
                }
                return .void;
            },
            .var_decl => |var_decl| {
                const expr_type = try self.typeCheck(var_decl.expr);
                if (!expr_type.equal(&var_decl.decl_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected type {any} in variable declaration expression, found type {any}", .{ var_decl.decl_type, expr_type }, var_decl.expr.index);
                    return Error.MismatchedTypes;
                }
                return .void;
            },
            .var_assign => |var_assign| {
                const expr_type = try self.typeCheck(var_assign.expr);
                const ident_type = &node.symbol_decl.?.data.var_decl.decl_type;
                if (!expr_type.equal(ident_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected type {any} in variable declaration expression, found type {any}", .{ ident_type, expr_type }, var_assign.expr.index);
                    return Error.MismatchedTypes;
                }
                return .void;
            },
            //else => return .void,
        }
    }
};
