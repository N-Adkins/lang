const std = @import("std");
const symbol = @import("symbol.zig");
const types = @import("types.zig");

pub const AstNode = struct {
    symbol_decl: ?*AstNode = null,
    index: usize,
    data: union(enum) {
        // Expressions
        integer_constant: struct { value: i64, },
        var_get: struct { name: []u8 },

        // Statements
        block: struct { list: std.ArrayListUnmanaged(*AstNode) },
        var_decl: struct { name: []u8, decl_type: types.Type, expr: *AstNode },
        var_assign: struct { name: []u8, expr: *AstNode },
        expr_statement: struct { expr: *AstNode },
    },

    pub fn deinit(self: *AstNode, allocator: std.mem.Allocator) void {
        switch (self.data) {
            .integer_constant => {},
            .var_get => |var_get| allocator.free(var_get.name),
            .block => |*block| {
                for (block.list.items) |node| {
                    node.deinit(allocator);
                    allocator.destroy(node);
                }
                block.*.list.deinit(allocator);
            },
            .var_decl => |var_decl| {
                allocator.free(var_decl.name);
                var_decl.expr.deinit(allocator);
                allocator.destroy(var_decl.expr);
            },
            .var_assign => |var_assign| {
                allocator.free(var_assign.name);
                var_assign.expr.deinit(allocator);
                allocator.destroy(var_assign.expr);
            },
            .expr_statement => |expr| {
                expr.expr.deinit(allocator);
                allocator.destroy(expr.expr);
            },
        } 
    }
};
