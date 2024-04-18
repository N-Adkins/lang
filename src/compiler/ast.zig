//! Abstract Syntax Tree, used in passes and code generation

const std = @import("std");
const types = @import("types.zig");

/// Abstract Syntax Tree Node, contains both
/// statements and expressions
pub const Node = struct {
    symbol_decl: ?*Node = null,
    index: usize,
    data: union(enum) {
        // Expressions
        integer_constant: struct { value: i64 },
        var_get: struct { name: []u8 },

        // Statements
        block: struct { list: std.ArrayListUnmanaged(*Node) },
        var_decl: struct { name: []u8, decl_type: types.Type, expr: *Node },
        var_assign: struct { name: []u8, expr: *Node },
    },

    /// Does not assume that self is heap allocated
    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.data) {
            .integer_constant => {},
            .var_get => |*var_get| allocator.free(var_get.name),
            .block => |*block| {
                for (block.list.items) |node| {
                    node.deinit(allocator);
                    allocator.destroy(node);
                }
                block.*.list.deinit(allocator);
            },
            .var_decl => |*var_decl| {
                var_decl.expr.deinit(allocator);
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
