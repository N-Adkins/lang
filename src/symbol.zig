const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");

pub const SymbolError = error{
    SymbolNotFound,
} || std.mem.Allocator.Error;

pub const SymbolTable = struct {
    parent: ?*SymbolTable,
    table: std.StringHashMap(types.Type),

    pub fn init(parent: ?*SymbolTable, allocator: *std.mem.Allocator) SymbolTable {
        return SymbolTable{
            .parent = parent,
            .table = std.StringHashMap(types.Type).init(allocator.*),
        };
    }

    pub fn deinit(self: *SymbolTable, allocator: *std.mem.Allocator) void {
        var iter = self.table.keyIterator();
        while (iter.next()) |key| {
            allocator.free(key.*);
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

    fn getSymbol(self: *SymbolTable, symbol: []const u8) SymbolError!*types.Type {
        if (self.table.get(symbol)) |*symbol_type| {
            return symbol_type;
        }

        if (self.parent) |parent| {
            return try parent.getSymbol(symbol);
        }

        return null;
    }

    fn setSymbol(self: *SymbolTable, symbol: []const u8, symbol_type: types.Type) SymbolError!void {
        try self.table.put(symbol, symbol_type);
    }
};

pub fn checkSymbols(root: *ast.Block) SymbolError!void {
    return checkBlock(root); 
}

fn checkExpression(expr: *ast.Expression) SymbolError!void {

}

fn checkStatement(scope: *ast.Block, statement: *ast.Statement) SymbolError!void {
    switch (statement) {
        .block => |block| try checkBlock(block),
        .variable_decl => |variable| {
            
        }
    }
}

fn checkBlock(scope: ?*ast.Block, block: *ast.Block) SymbolError!void {

}
