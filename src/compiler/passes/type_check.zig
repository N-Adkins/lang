//! Type-checking pass, assumes symbols have been populated and ensures
//! that all types are correct.
//! TODO:
//! Implement checks to ensure that all control paths
//! have a return statement

const std = @import("std");
const ast = @import("../ast.zig");
const builtin = @import("../builtin.zig");
const err = @import("../error.zig");
const types = @import("../types.zig");

pub const Error = error{
    MismatchedTypes,
} || std.mem.Allocator.Error;

const Stack = struct {
    const Node = struct {
        next: ?*Node = null,
        data: types.Type,
    };
    head: ?*Node = null,

    pub fn deinit(self: *Stack, allocator: std.mem.Allocator) void {
        while (self.pop(allocator)) |type_decl| {
            var deinit_decl = type_decl;
            deinit_decl.deinit(allocator);
        }
    }

    pub fn push(self: *Stack, allocator: std.mem.Allocator, type_decl: types.Type) Error!*types.Type {
        const node = try allocator.create(Node);
        node.data = type_decl;
        node.next = self.head;
        self.head = node;
        return &node.data;
    }

    pub fn pop(self: *Stack, allocator: std.mem.Allocator) ?types.Type {
        if (self.head) |head| {
            const ret = head.data;
            self.head = head.next;
            allocator.destroy(head);
            return ret;
        } else {
            return null;
        }
    }

    pub fn peek(self: *Stack) ?*types.Type {
        if (self.head) |head| {
            return &head.data;
        }
        return null;
    }
};

pub const Pass = struct {
    root: *ast.Node,
    func_stack: Stack = Stack{},
    err_ctx: *err.ErrorContext,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, root: *ast.Node) Error!Pass {
        var pass = Pass{
            .root = root,
            .err_ctx = err_ctx,
            .allocator = allocator,
        };

        // Push main function signature
        const void_type = try allocator.create(types.Type);
        void_type.* = .void;
        _ = try pass.func_stack.push(allocator, types.Type{ .function = .{ .ret = void_type } });

        return pass;
    }

    pub fn deinit(self: *Pass) void {
        self.func_stack.deinit(self.allocator);
    }

    pub fn run(self: *Pass) Error!void {
        _ = try self.typeCheck(self.root);
    }

    fn typeCheck(self: *Pass, node: *ast.Node) Error!types.Type {
        switch (node.data) {
            .number_constant => return .number,
            .string_constant => return .string,
            .var_get => |_| return try node.symbol_decl.?.decl_type.?.dupe(self.allocator),
            .block => |*block| {
                for (block.list.items) |statement| {
                    var stmt_type = try self.typeCheck(statement);
                    stmt_type.deinit(self.allocator);
                }
                return .void;
            },
            .binary_op => |*binary| {
                const lhs_type = try self.typeCheck(binary.lhs);
                var rhs_type = try self.typeCheck(binary.rhs);
                defer rhs_type.deinit(self.allocator);
                if (!lhs_type.equal(&rhs_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected type \"{any}\" in right hand of binary expression, found type \"{any}\"", .{ lhs_type, rhs_type }, binary.rhs.index);
                    return Error.MismatchedTypes;
                }
                return lhs_type;
            },
            .unary_op => |_| return try self.checkUnary(node),
            .function_decl => |*func_decl| {
                var arg_types = std.ArrayListUnmanaged(types.Type){};
                errdefer {
                    for (arg_types.items) |*arg_type| {
                        arg_type.deinit(self.allocator);
                    }
                    arg_types.deinit(self.allocator);
                }

                for (func_decl.args.items) |arg| {
                    try arg_types.append(self.allocator, try arg.decl_type.?.dupe(self.allocator));
                }

                var ret = try self.allocator.create(types.Type);
                ret.* = try func_decl.ret_type.dupe(self.allocator);
                errdefer {
                    ret.deinit(self.allocator);
                    self.allocator.destroy(ret);
                }

                var func_type = types.Type{
                    .function = .{
                        .args = arg_types,
                        .ret = ret,
                    },
                };
                errdefer func_type.deinit(self.allocator);

                var dupe = try func_type.dupe(self.allocator);
                defer dupe.deinit(self.allocator);

                _ = try self.func_stack.push(self.allocator, dupe);

                var body_type = try self.typeCheck(func_decl.body);
                defer body_type.deinit(self.allocator);

                _ = self.func_stack.pop(self.allocator);

                return func_type;
            },
            .builtin_call => |*call| {
                const data: builtin.Data = builtin.lookup.kvs[call.idx].value;
                for (call.args) |arg| {
                    var arg_type = try self.typeCheck(arg);
                    arg_type.deinit(self.allocator);
                }
                return try data.ret_type.dupe(self.allocator);
            },
            .var_decl => |*var_decl| {
                if (var_decl.symbol.decl_type) |*decl_type| {
                    var expr_type = try self.typeCheck(var_decl.expr);
                    defer expr_type.deinit(self.allocator);
                    if (!expr_type.equal(decl_type)) {
                        try self.err_ctx.newError(.mismatched_types, "Expected type \"{any}\" in variable declaration expression, found type \"{any}\"", .{ decl_type, expr_type }, var_decl.expr.index);
                        return Error.MismatchedTypes;
                    }
                } else {
                    const expr_type = try self.typeCheck(var_decl.expr);
                    if (expr_type.equal(&.void)) {
                        try self.err_ctx.newError(.mismatched_types, "Void is not a valid inferred variable type", .{}, var_decl.expr.index);
                        return Error.MismatchedTypes;
                    }
                    var_decl.symbol.decl_type = expr_type;
                }
                return .void;
            },
            .var_assign => |*var_assign| {
                var expr_type = try self.typeCheck(var_assign.expr);
                defer expr_type.deinit(self.allocator);
                const ident_type = &node.symbol_decl.?.decl_type.?;
                if (!expr_type.equal(ident_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected type \"{any}\" in variable declaration expression, found type \"{any}\"", .{ ident_type, expr_type }, var_assign.expr.index);
                    return Error.MismatchedTypes;
                }
                return .void;
            },
            .return_stmt => |*ret| {
                var ret_type: types.Type = if (ret.expr) |expr| try self.typeCheck(expr) else .void;
                defer ret_type.deinit(self.allocator);
                const func_ret_type = self.func_stack.head.?.data.function.ret;
                if (!ret_type.equal(func_ret_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected type \"{any}\" in function return statement, found type \"{any}\"", .{ func_ret_type, ret_type }, node.index);
                    return Error.MismatchedTypes;
                }
                return .void;
            },
        }
    }

    /// Made this its own function because it's long
    pub fn checkUnary(self: *Pass, node: *ast.Node) Error!types.Type {
        const unary = &node.data.unary_op;

        var expr_type = try self.typeCheck(unary.expr);
        defer expr_type.deinit(self.allocator);

        switch (unary.op) {
            .call => |call| {
                var arg_types = std.ArrayListUnmanaged(types.Type){};
                defer {
                    for (arg_types.items) |*arg_type| {
                        arg_type.deinit(self.allocator);
                    }
                    arg_types.deinit(self.allocator);
                }

                for (call.args.items) |expr| {
                    try arg_types.append(self.allocator, try self.typeCheck(expr));
                }

                switch (expr_type) {
                    .function => |func| {
                        if (func.args.items.len != arg_types.items.len) {
                            try self.err_ctx.newError(.mismatched_types, "Expected {d} arguments to function call, found {d}", .{ func.args.items.len, arg_types.items.len }, node.index);
                            return Error.MismatchedTypes;
                        }
                        for (0..func.args.items.len) |i| {
                            if (!func.args.items[i].equal(&arg_types.items[i])) {
                                try self.err_ctx.newError(.mismatched_types, "Expected type \"{any}\" in function call argument number {d}, found {any}", .{ func.args.items[i], i, arg_types.items[i] }, node.index);
                                return Error.MismatchedTypes;
                            }
                        }
                        return func.ret.*;
                    },
                    else => {
                        try self.err_ctx.newError(.mismatched_types, "Expected function type in call expression, found type {any}", .{expr_type}, node.index);
                        return Error.MismatchedTypes;
                    },
                }
            },
            else => unreachable,
        }
    }
};
