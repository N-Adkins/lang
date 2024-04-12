const std = @import("std");
const symbol = @import("symbol.zig");

pub const Expression = union(enum) {
    number_constant: i64,
    variable_get: []u8,
    function_decl: struct { args: std.ArrayList([]u8), body: Block },
    call: struct { callee: *Expression, args: std.ArrayList(Expression) },

    pub fn deinit(self: *Expression, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .number_constant => {},
            .variable_get => |*variable| {
                allocator.free(variable.*);
            },
            .function_decl => |*func| {
                for (func.args.items) |arg| {
                    allocator.free(arg);
                }
                func.args.deinit();
                func.body.deinit(allocator);
            },
            .call => |*call| {
                call.args.deinit();
                call.callee.deinit(allocator);
            },
        }
        allocator.destroy(self);
    }
};

pub const Statement = union(enum) {
    variable_decl: struct { name: []const u8, value: *Expression },
    block: Block,

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .variable_decl => |*decl| {
                allocator.free(decl.name);
                decl.value.deinit(allocator);
            },
            .block => |*block| {
                block.deinit(allocator);
            },
        }
        allocator.destroy(self);
    }
};

pub const Block = struct {
    statements: std.ArrayList(*Statement),
    symbols: symbol.SymbolTable,

    pub fn init(parent: ?*Block, allocator: std.mem.Allocator) Block {
        const symbol_table = if (parent) |parent_block| symbol.SymbolTable.init(&parent_block.symbols, allocator) else symbol.SymbolTable.init(null, allocator);
        return Block{
            .statements = std.ArrayList(*Statement).init(allocator),
            .symbols = symbol_table,
        };
    }

    pub fn deinit(self: *Block, allocator: std.mem.Allocator) void {
        for (self.statements.items) |statement| {
            statement.deinit(allocator);
        }
        self.statements.deinit();
        self.symbols.deinit();
    }
};
