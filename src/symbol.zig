const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");

pub const SymbolError = error{
    SymbolNotFound,
    SymbolShadowing,
    TypeMismatch,
} || std.mem.Allocator.Error;

pub const SymbolTable = struct {
    parent: ?*SymbolTable,
    table: std.StringHashMap(*types.Type),
    allocator: std.mem.Allocator,

    pub fn init(parent: ?*SymbolTable, allocator: std.mem.Allocator) SymbolTable {
        return SymbolTable{
            .parent = parent,
            .table = std.StringHashMap(*types.Type).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SymbolTable) void {
        var iter = self.table.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
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

    fn getSymbol(self: *SymbolTable, symbol: []const u8) ?**types.Type {
        if (self.table.getPtr(symbol)) |symbol_type| {
            return symbol_type;
        }

        if (self.parent) |parent| {
            return parent.getSymbol(symbol);
        }

        return null;
    }

    fn setSymbol(self: *SymbolTable, symbol: []const u8, symbol_type: *types.Type) SymbolError!void {
        if (self.getSymbol(symbol)) |value| {
            value.* = symbol_type;
            return;
        }

        const duped_symbol = try self.allocator.dupe(u8, symbol);
        errdefer self.allocator.free(duped_symbol);

        try self.table.put(duped_symbol, symbol_type);
    }
};
