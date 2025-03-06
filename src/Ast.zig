const std = @import("std");
const ErrorContext = @import("ErrorContext.zig");
const Source = ErrorContext.Source;
const Self = @This();

pub const Symbol = struct {
    name: []const u8,
    type: TypeId,
};

pub const Type = union(enum) {
    pub const BuiltinTable = std.StaticStringMap(Type).initComptime(.{
        .{ "void", .void },
    });

    void,

    pub fn eql(lhs: *const Type, rhs: *const Type) bool {
        return @intFromEnum(lhs.*) == @intFromEnum(rhs.*);
    }
};

pub const TypeTable = struct {
    types: std.ArrayListUnmanaged(Type) = .empty,

    pub fn getOrInsert(self: *TypeTable, allocator: std.mem.Allocator, @"type": Type) !TypeId {
        for (self.types.items, 0..) |*cur_type, i| {
            if (cur_type.eql(@"type")) {
                return @enumFromInt(i);
            }
        }
        const id: TypeId = @enumFromInt(self.types.items.len);
        try self.types.append(allocator, @"type");
        return id;
    }
};

pub const SymbolTable = struct {
    parent: ?*SymbolTable = null,
    symbols: std.ArrayListUnmanaged(Symbol) = .empty,

    pub fn find(self: *SymbolTable, name: []const u8) ?SymbolId {
        for (self.symbols.items, 0..) |*symbol, i| {
            if (std.mem.eql(symbol.name, name)) {
                return @enumFromInt(i);
            }
        }

        if (self.parent) |parent_table| {
            return parent_table.find(name);
        }

        return null;
    }

    pub fn getOrInsert(self: *SymbolTable, allocator: std.mem.Allocator, symbol: Symbol) !SymbolId {
        if (self.find(symbol.name)) |id| {
            return id;
        }
        const id: SymbolId = @enumFromInt(self.symbols.items.len);
        try self.symbols.append(allocator, symbol);
        return id;
    }
};

pub const SymbolId = enum(usize) { invalid = std.math.maxInt(usize) };
pub const TypeId = enum(usize) { invalid = std.math.maxInt(usize) };

pub const Node = struct {
    pub const Kind = union(enum) {
        pub const FunctionArg = struct {
            name: []const u8,
            type: TypeId,
            symbol: SymbolId = .invalid,
        };

        func_decl: struct {
            name: []const u8,
            args: []FunctionArg,
            body: []*Node,
            return_type: TypeId,
        },

        block: []*Node,

        var_decl: struct {
            name: []const u8,
            type: TypeId,
            value: *Node,
        },

        var_get: []const u8,

        int_literal: i64,
    };

    kind: Kind,
    source: *const Source,
    source_index: usize,
    symbol: SymbolId = .invalid,
};

arena_allocator: std.heap.ArenaAllocator,
body: []*Node = undefined,
type_table: TypeTable = .{},
symbol_table: SymbolTable = .{},

pub fn init(backing_allocator: std.mem.Allocator) Self {
    const arena_allocator = std.heap.ArenaAllocator.init(backing_allocator);
    return .{
        .arena_allocator = arena_allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.arena_allocator.deinit();
}

pub fn arena(self: *Self) std.mem.Allocator {
    return self.arena_allocator.allocator();
}
