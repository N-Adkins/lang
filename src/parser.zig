const std = @import("std");
const lexer = @import("lexer.zig");

pub const ParseError = error {
    UnexpectedToken,
    UnexpectedEnd,
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
            },
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
            },
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
        for (self.statements.items) |statement| {
            statement.deinit();
        }
        self.statements.deinit();
    }
};

pub const Parser = struct {
    lexer: *lexer.Lexer,
    allocator: *std.mem.Allocator,
    root: Block,
    current: ?lexer.Token = null,
    previous: ?lexer.Token = null,

    pub fn init(lex: *lexer.Lexer, allocator: *std.mem.Allocator) Parser {
        return Parser{
            .lexer = lex,
            .allocator = allocator,
            .root = Block.init(allocator),
        };
    }

    pub fn parse(self: *Parser) ParseError!void {
        self.nextToken();
        while (self.lexer.queue.len > 0) {
            const statement = try parseStatement();
            try self.root.statements.append(statement);
        }
    }

    fn parseStatement(self: *Parser) ParseError!*Statement {
        if (self.current == null) {
            return ParseError.UnexpectedEnd;
        }

        const statement = switch (self.current.?.tag) {
            .keyword_var => try self.parseStatement(),
        };
        errdefer statement.deinit();

        _ = try self.expectToken(.semicolon);

        return statement;
    }

    fn expectToken(self: *Parser, tag: lexer.TokenTag) ParseError!lexer.Token {
        if (self.current) |current| {
            if (current.tag == tag) {
                self.nextToken();
                return current;
            } else {
                return ParseError.UnexpectedToken;
            }
        } else {
            return ParseError.UnexpectedToken;
        }
    }

    fn nextToken(self: *Parser) lexer.Token {
        self.previous = self.current;
        self.current = self.lexer.nextToken();
        return self.current;
    }
};
