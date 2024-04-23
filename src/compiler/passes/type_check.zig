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

    pub fn push(self: *Stack, allocator: std.mem.Allocator, type_decl: types.Type) Error!*types.Type {
        const node = try allocator.create(Node);
        node.data = type_decl;
        node.next = self.head;
        self.head = node;
        return &node.data;
    }

    pub fn pop(self: *Stack) ?types.Type {
        if (self.head) |head| {
            const ret = head.data;
            self.head = head.next;
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

    pub fn init(allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, root: *ast.Node) Pass {
        return Pass{
            .root = root,
            .err_ctx = err_ctx,
            .allocator = allocator,
        };
    }

    pub fn run(self: *Pass) Error!void {
        var void_type: types.Type = .void;
        _ = try self.func_stack.push(self.allocator, types.Type{ .function = .{ .ret = &void_type } });
        _ = try self.typeCheck(self.root);
    }

    fn typeCheck(self: *Pass, node: *ast.Node) Error!types.Type {
        switch (node.data) {
            .number_constant => return .number,
            .boolean_constant => return .boolean,
            .string_constant => return .string,
            .var_get => |_| return {
                if (node.symbol_decl.?.function_decl) |func| {
                    return func.data.function_decl.func_type;
                }
                return node.symbol_decl.?.decl_type.?;
            },
            .block => |*block| {
                for (block.list.items) |statement| {
                    _ = try self.typeCheck(statement);
                }
                return .void;
            },
            .binary_op => |*binary| {
                const lhs_type = try self.typeCheck(binary.lhs);
                const rhs_type = try self.typeCheck(binary.rhs);
                switch (binary.op) {
                    .boolean_and, .boolean_or => {
                        const bool_type: types.Type = .boolean;
                        if (!lhs_type.equal(&bool_type) != !rhs_type.equal(&bool_type)) {
                            try self.err_ctx.newError(.mismatched_types, "Expected boolean type on both sides of boolean statement, found types \"{any}\" and \"{any}\"", .{ lhs_type, rhs_type }, binary.lhs.index);
                            return Error.MismatchedTypes;
                        }
                        return .boolean;
                    },
                    .equals, .not_equals => {
                        if (!lhs_type.equal(&rhs_type)) {
                            try self.err_ctx.newError(.mismatched_types, "Expected type \"{any}\" in right hand of comparison, found type \"{any}\"", .{ lhs_type, rhs_type }, binary.rhs.index);
                            return Error.MismatchedTypes;
                        }
                        return .boolean;
                    },
                    else => {
                        if (!lhs_type.equal(&rhs_type)) {
                            try self.err_ctx.newError(.mismatched_types, "Expected type \"{any}\" in right hand of binary expression, found type \"{any}\"", .{ lhs_type, rhs_type }, binary.rhs.index);
                            return Error.MismatchedTypes;
                        }
                        return lhs_type;
                    },
                }
            },
            .unary_op => |_| return try self.checkUnary(node),
            .function_decl => |*func_decl| {
                var arg_types = std.ArrayListUnmanaged(types.Type){};

                for (func_decl.args.items) |arg| {
                    try arg_types.append(self.allocator, arg.decl_type.?);
                }

                const ret = try self.allocator.create(types.Type);
                ret.* = func_decl.ret_type;

                const func_type = types.Type{
                    .function = .{
                        .args = arg_types,
                        .ret = ret,
                    },
                };

                func_decl.func_type = func_type;

                _ = try self.func_stack.push(self.allocator, func_type);

                _ = try self.typeCheck(func_decl.body);

                _ = self.func_stack.pop();

                return func_type;
            },
            .builtin_call => |*call| {
                const data: builtin.Data = builtin.lookup.kvs[call.idx].value;
                for (call.args) |arg| {
                    _ = try self.typeCheck(arg);
                }
                return data.ret_type;
            },
            .array_init => |*array| {
                // allow empty array initialization later, it'll be void for now
                // I'll have to implement a special case disallowing type inference
                // for empty ones
                if (array.items.items.len <= 0) {
                    const void_type = try self.allocator.create(types.Type);
                    void_type.* = .void;
                    return types.Type{ .array = .{ .base = void_type } };
                }

                const array_type = try self.typeCheck(array.items.items[0]);
                for (array.items.items) |item| {
                    const item_type = try self.typeCheck(item);
                    if (!item_type.equal(&array_type)) {
                        try self.err_ctx.newError(.mismatched_types, "Expected type \"{any}\" in array initialization, found type \"{any}\"", .{ array_type, item_type }, item.index);
                        return Error.MismatchedTypes;
                    }
                }

                const heap_type = try self.allocator.create(types.Type);
                heap_type.* = array_type;

                return types.Type{ .array = .{ .base = heap_type } };
            },
            .var_decl => |*var_decl| {
                if (var_decl.symbol.decl_type) |*decl_type| {
                    var expr_type = try self.typeCheck(var_decl.expr);
                    if (!expr_type.equal(decl_type)) {
                        try self.err_ctx.newError(.mismatched_types, "Expected type \"{any}\" in variable declaration expression, found type \"{any}\"", .{ decl_type, expr_type }, var_decl.expr.index);
                        return Error.MismatchedTypes;
                    }
                } else {
                    var expr_type = try self.typeCheck(var_decl.expr);
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
                const ident_type = &node.symbol_decl.?.decl_type.?;
                if (!expr_type.equal(ident_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected type \"{any}\" in variable declaration expression, found type \"{any}\"", .{ ident_type, expr_type }, var_assign.expr.index);
                    return Error.MismatchedTypes;
                }
                return .void;
            },
            .array_set => |*array_set| {
                const const_array_type: types.Type = .{ .array = undefined };
                const const_num_type: types.Type = .number;
                const array_type = try self.typeCheck(array_set.array);
                const index_type = try self.typeCheck(array_set.index);
                const expr_type = try self.typeCheck(array_set.expr);
                if (@intFromEnum(array_type) != @intFromEnum(const_array_type)) { // don't want deep check
                    try self.err_ctx.newError(.mismatched_types, "Expected array type on left of array set, found type {any}", .{array_type}, array_set.expr.index);
                    return Error.MismatchedTypes;
                }
                if (!index_type.equal(&const_num_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected number type as index, found type {any}", .{index_type}, array_set.index.index);
                    return Error.MismatchedTypes;
                }
                if (!array_type.array.base.equal(&expr_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected type \"{any}\" on right side of array set, found type {any}", .{ array_type.array.base, expr_type }, array_set.expr.index);
                    return Error.MismatchedTypes;
                }
                return .void;
            },
            .if_stmt => |*if_stmt| {
                const expr_type = try self.typeCheck(if_stmt.expr);
                const bool_type: types.Type = .boolean;
                if (!expr_type.equal(&bool_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected boolean type in if statement expresion, found type \"{any}\"", .{expr_type}, node.index);
                    return Error.MismatchedTypes;
                }
                _ = try self.typeCheck(if_stmt.true_body);
                if (if_stmt.false_body) |false_body| {
                    _ = try self.typeCheck(false_body);
                }
                return .void;
            },
            .return_stmt => |*ret| {
                const ret_type: types.Type = if (ret.expr) |expr| try self.typeCheck(expr) else .void;
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
        const expr_type = try self.typeCheck(unary.expr);
        switch (unary.op) {
            .call => |call| {
                var arg_types = std.ArrayListUnmanaged(types.Type){};

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
            .index => |*index| {
                const array_type: types.Type = .{ .array = undefined };
                const num_type: types.Type = .number;
                if (@intFromEnum(expr_type) != @intFromEnum(array_type)) { // don't want deep check
                    try self.err_ctx.newError(.mismatched_types, "Expected array type on left of indexing, found type {any}", .{expr_type}, node.index);
                    return Error.MismatchedTypes;
                }
                const index_type = try self.typeCheck(index.index);
                if (!index_type.equal(&num_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected number type as index, found type {any}", .{index_type}, node.index);
                    return Error.MismatchedTypes;
                }
                return expr_type.array.base.*;
            },
            else => unreachable,
        }
    }
};
