const std = @import("std");
const lexer = @import("lexer.zig");

pub const ParseError = error {
    
} || std.mem.Allocator.Error;

pub const Expression = union(enum) {
    number_constant: i64,
    call: struct { callee: *Expression, args: std.ArrayList(Expression) },
};

pub const Statement = union(enum) {
    variable_decl: struct { name: []const u8, value: *Expression },
    block: Block,
};

pub const Block = struct {
    statements: std.ArrayList(Statement),
    pub fn init(allocator: *std.mem.Allocator) Block {
        return Block{
            .statements = std.ArrayList(Statement).init(allocator),
        };
    }

    pub fn deinit(self: *Block) void {
        self.statements.deinit(); 
    }
};

pub const Parser = struct {
    lexer: *lexer.Lexer,
};
