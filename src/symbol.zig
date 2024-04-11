const std = @import("std");
const types = @import("types.zig");

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
};
