//! Abstract Syntax Tree, used in passes and code generation

const std = @import("std");
const types = @import("types.zig");

pub const Operator = union(enum) {
    add,
    sub,
    mul,
    div,
    call: struct { args: std.ArrayListUnmanaged(*Node) },

    pub fn deinit(self: *Operator, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .call => |*call| {
                for (call.args.items) |arg| {
                    arg.deinit(allocator);
                    allocator.destroy(arg);
                }
                call.args.deinit(allocator);
            },
            else => {},
        }
    }
};

pub const FunctionArg = struct {
    name: []const u8,
    arg_type: types.Type,
};

/// Abstract Syntax Tree Node, contains both
/// statements and expressions
pub const Node = struct {
    symbol_decl: ?*Node = null,
    index: usize,
    data: union(enum) {
        // Expressions
        integer_constant: struct { value: i64 },
        var_get: struct { name: []u8 },
        unary_op: struct { op: Operator, expr: *Node },
        binary_op: struct { op: Operator, lhs: *Node, rhs: *Node },
        function_decl: struct { args: std.ArrayListUnmanaged(FunctionArg), ret_type: types.Type, body: *Node },

        // Statements
        block: struct { list: std.ArrayListUnmanaged(*Node) },
        var_decl: struct { name: []u8, decl_type: ?types.Type, expr: *Node },
        var_assign: struct { name: []u8, expr: *Node },
    },

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.data) {
            .integer_constant => {},
            .var_get => |*var_get| allocator.free(var_get.name),
            .unary_op => |*unary| {
                unary.op.deinit(allocator);
                unary.expr.deinit(allocator);
                allocator.destroy(unary.expr);
            },
            .binary_op => |*binary| {
                binary.op.deinit(allocator);
                binary.lhs.deinit(allocator);
                binary.rhs.deinit(allocator);
                allocator.destroy(binary.lhs);
                allocator.destroy(binary.rhs);
            },
            .function_decl => |*func_decl| {
                for (func_decl.args.items) |*arg| {
                    allocator.free(arg.name);
                    arg.arg_type.deinit(allocator);
                }
                func_decl.args.deinit(allocator);
                func_decl.ret_type.deinit(allocator);
                func_decl.body.deinit(allocator);
                allocator.destroy(func_decl.body);
            },
            .block => |*block| {
                for (block.list.items) |node| {
                    node.deinit(allocator);
                    allocator.destroy(node);
                }
                block.*.list.deinit(allocator);
            },
            .var_decl => |*var_decl| {
                var_decl.expr.deinit(allocator);
                if (var_decl.decl_type) |*decl_type| {
                    decl_type.deinit(allocator);
                }
                allocator.free(var_decl.name);
                allocator.destroy(var_decl.expr);
            },
            .var_assign => |*var_assign| {
                var_assign.expr.deinit(allocator);
                allocator.free(var_assign.name);
                allocator.destroy(var_assign.expr);
            },
        }
    }
};
