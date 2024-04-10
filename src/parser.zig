const std = @import("std");
const lexer = @import("lexer.zig");

pub const ParseError = error {
    
} || std.mem.Allocator.Error;

pub const Expression = union(enum) {
    number_constant: i64,
    function_decl: struct { args: std.ArrayList([]u8), body: Block },
    call: struct { callee: *Expression, args: std.ArrayList(Expression) },

    pub fn deinit(self: *Expression, allocator: *std.mem.Allocator) void {
        switch (self.*) {
            .number_constant => {},
            .function_decl => |func| {
                for (func.args.items) |arg| {
                    allocator.free(arg);
                }
                func.args.deinit();
                func.body.deinit();
            },
            .call => |call| {
                call.args.deinit();
                call.callee.deinit(allocator);
            }
        }
    }
};

pub const Statement = union(enum) {
    variable_decl: struct { name: []const u8, value: *Expression },
    block: Block,

    pub fn deinit(self: *Statement, allocator: *std.mem.Allocator) void {
        switch (self.*) {
            .variable_decl => |decl| {
                allocator.free(decl.name);
                decl.value.deinit(allocator);
            }
        }
    }
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
