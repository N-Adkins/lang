const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");

pub const SymbolError = error{
    SymbolNotFound,
    SymbolShadowing,
} || std.mem.Allocator.Error;

pub const SymbolTable = struct {
    parent: ?*SymbolTable,
    table: std.StringHashMap(types.Type),
    allocator: std.mem.Allocator,

    pub fn init(parent: ?*SymbolTable, allocator: std.mem.Allocator) SymbolTable {
        return SymbolTable{
            .parent = parent,
            .table = std.StringHashMap(types.Type).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SymbolTable) void {
        var iter = self.table.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.table.deinit();
    }

    fn checkSymbolExists(self: *SymbolTable, symbol: []const u8) SymbolError!void {
        if (self.table.get(symbol)) |_| {
            return;
        }

        if (self.parent) |parent| {
            try parent.checkSymbolExists(symbol);
        }
    }

    fn getSymbol(self: *SymbolTable, symbol: []const u8) ?*types.Type {
        if (self.table.getPtr(symbol)) |symbol_type| {
            return symbol_type;
        }

        if (self.parent) |parent| {
            return parent.getSymbol(symbol);
        }

        return null;
    }

    fn setSymbol(self: *SymbolTable, symbol: []const u8, symbol_type: types.Type) SymbolError!void {
        if (self.getSymbol(symbol)) |value| {
            value.* = symbol_type;
            return;
        }

        const duped_symbol = try self.allocator.dupe(u8, symbol);
        try self.table.put(duped_symbol, symbol_type);
    }
};

pub fn checkSymbols(root: *ast.Block) SymbolError!void {
    return checkBlock(root);
}

fn checkExpression(scope: *ast.Block, expr: *ast.Expression) SymbolError!void {
    switch (expr.*) {
        .call => |call| try checkExpression(call.callee),
        .variable_get => |variable| {
            if (scope.symbols.getSymbol(variable) == null) {
                return SymbolError.SymbolNotFound;
            }
        },
        .function_decl => |func| {
            try checkBlock(scope, func.body);
        },
        .number_constant => {},
    }
}

fn checkStatement(scope: *ast.Block, statement: *ast.Statement) SymbolError!void {
    switch (statement.*) {
        .block => |*block| try checkBlock(block),
        .variable_decl => |variable| {
            if (scope.symbols.getSymbol(variable.name)) |_| {
                return SymbolError.SymbolShadowing;
            }
            try scope.symbols.setSymbol(variable.name, .number); // number is placeholder
        },
    }
}

fn checkBlock(block: *ast.Block) SymbolError!void {
    for (block.statements.items) |statement| {
        try checkStatement(block, statement);
    }
}
