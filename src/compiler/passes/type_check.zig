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
            .int_constant => return .int,
            .boolean_constant => return .boolean,
            .string_constant => return .string,
            .var_get => |_| return {
                if (node.symbol_decl.?.function_decl) |func| {
                    return func.data.function_value.func_type;
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
                    .greater_than, .less_than, .greater_than_equals, .less_than_equals => {
                        const int_type: types.Type = .int;
                        if (!lhs_type.equal(&rhs_type) or @intFromEnum(lhs_type) != @intFromEnum(int_type) or @intFromEnum(rhs_type) != @intFromEnum(int_type)) {
                            try self.err_ctx.newError(.mismatched_types, "Expected number types in binary expression, found type \"{any}\" and \"{any}\"", .{ lhs_type, rhs_type }, binary.rhs.index);
                            return Error.MismatchedTypes;
                        }
                        return .boolean;
                    },
                    .add, .sub, .mul, .div => {
                        const int_type: types.Type = .int;
                        if (!lhs_type.equal(&rhs_type) or @intFromEnum(lhs_type) != @intFromEnum(int_type) or @intFromEnum(rhs_type) != @intFromEnum(int_type)) {
                            try self.err_ctx.newError(.mismatched_types, "Expected number types int binary expression, found type \"{any}\" and \"{any}\"", .{ lhs_type, rhs_type }, binary.rhs.index);
                            return Error.MismatchedTypes;
                        }
                        return .int;
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
            .function_value => |*func| {
                var arg_types = std.ArrayListUnmanaged(types.Type){};

                for (func.args.items) |arg| {
                    try arg_types.append(self.allocator, arg.decl_type.?);
                }

                const ret = try self.allocator.create(types.Type);
                ret.* = func.ret_type;

                const func_type = types.Type{
                    .function = .{
                        .args = arg_types,
                        .ret = ret,
                    },
                };

                func.func_type = func_type;

                _ = try self.func_stack.push(self.allocator, func_type);

                _ = try self.typeCheck(func.body);

                _ = self.func_stack.pop();

                return func_type;
            },
            .builtin_call => |*call| {
                const data: builtin.Data = blk: {
                    for (builtin.lookup.kvs) |pairs| {
                        if (pairs.value.id == call.idx) {
                            break :blk pairs.value;
                        }
                    }
                    unreachable;
                };

                // if ret type is null, then assume it is the same as a null
                // argument
                const ret_type = if (data.ret_type) |ret| ret else blk: {
                    break :blk try self.typeCheck(call.args[0]);
                };

                const array_type: ?types.Type = if (data.array_inner_type) blk: {
                    const first_arg = try self.typeCheck(call.args[0]);
                    switch (first_arg) {
                        .array => |array| {
                            break :blk array.base.*;
                        },
                        else => {
                            try self.err_ctx.newError(.mismatched_types, "Expected array in builtin function call, found type \"{any}\"", .{ first_arg }, call.args[0].index);
                            return Error.MismatchedTypes;
                        }
                    }
                } else null;

                for (0..call.args.len) |i| {
                    const arg = call.args[i];
                    const arg_type = try self.typeCheck(arg);
                    if (data.arg_types) |arg_types| {
                        const correct_type = if (data.deep_check_types) blk: {
                            for (arg_types[i].?) |*this_arg| {
                                if (arg_type.equal(this_arg)) {
                                    break :blk true;
                                }
                            }
                            break :blk false;
                        } else blk: {
                            if (array_type != null and arg_types[i] == null) {
                                if (@intFromEnum(array_type.?) == @intFromEnum(arg_type)) {
                                    break :blk true;
                                } else {
                                    break :blk false;
                                }
                            }
                            for (arg_types[i].?) |this_arg| {
                                if (@intFromEnum(this_arg) == @intFromEnum(arg_type)) {
                                    break :blk true;
                                }
                            }
                            break :blk false;
                        };

                        if (!correct_type) {
                            try self.err_ctx.newError(.mismatched_types, "Expected type \"{any}\" in builtin function call, found type \"{any}\"", .{ arg_types[i], arg_type }, arg.index);
                            return Error.MismatchedTypes;
                        }
                    }
                }
                return ret_type;
            },
            .array_init => |*array| {
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
                const void_type: types.Type = .void;
                const void_array: types.Type = .{ .array = .{ .base = @constCast(&void_type) } };
                if (var_decl.symbol.decl_type) |*decl_type| {
                    var expr_type = try self.typeCheck(var_decl.expr);
                    if (expr_type.equal(&void_array)) {
                        return .void;
                    } else if (!expr_type.equal(decl_type)) {
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
            .while_loop => |*while_loop| {
                const bool_type: types.Type = .boolean;
                const expr_type = try self.typeCheck(while_loop.expr);
                if (!expr_type.equal(&bool_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected boolean in while loop expression, found type {any}", .{expr_type}, while_loop.expr.index);
                    return Error.MismatchedTypes;
                }
                _ = try self.typeCheck(while_loop.body);
                return .void;
            },
            .for_loop => |*for_loop| {
                const bool_type: types.Type = .boolean;
                _ = try self.typeCheck(for_loop.init);
                const cond_type = try self.typeCheck(for_loop.condition);
                if (!cond_type.equal(&bool_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected boolean in for loop condition, found type {any}", .{cond_type}, for_loop.condition.index);
                    return Error.MismatchedTypes;
                }
                _ = try self.typeCheck(for_loop.after);
                _ = try self.typeCheck(for_loop.body);
                return .void;
            },
            .array_set => |*array_set| {
                const const_array_type: types.Type = .{ .array = undefined };
                const const_int_type: types.Type = .int;
                const array_type = try self.typeCheck(array_set.array);
                const index_type = try self.typeCheck(array_set.index);
                const expr_type = try self.typeCheck(array_set.expr);
                if (@intFromEnum(array_type) != @intFromEnum(const_array_type)) { // don't want deep check
                    try self.err_ctx.newError(.mismatched_types, "Expected array type on left of array set, found type {any}", .{array_type}, array_set.expr.index);
                    return Error.MismatchedTypes;
                }
                if (!index_type.equal(&const_int_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected integer type as index, found type {any}", .{index_type}, array_set.index.index);
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
                const int_type: types.Type = .int;
                if (@intFromEnum(expr_type) != @intFromEnum(array_type)) { // don't want deep check
                    try self.err_ctx.newError(.mismatched_types, "Expected array type on left of indexing, found type {any}", .{expr_type}, node.index);
                    return Error.MismatchedTypes;
                }
                const index_type = try self.typeCheck(index.index);
                if (!index_type.equal(&int_type)) {
                    try self.err_ctx.newError(.mismatched_types, "Expected integer type as index, found type {any}", .{index_type}, node.index);
                    return Error.MismatchedTypes;
                }
                return expr_type.array.base.*;
            },
            else => unreachable,
        }
    }
};
