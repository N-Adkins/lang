const std = @import("std");
const lexer = @import("lexer.zig");

pub const ParseError = error {
    UnexpectedToken,
    UnexpectedEnd,
} || std.mem.Allocator.Error;

pub const Expression = union(enum) {
    number_constant: i64,
    variable_get: []u8,
    function_decl: struct { args: std.ArrayList([]u8), body: Block },
    call: struct { callee: *Expression, args: std.ArrayList(Expression) },

    pub fn deinit(self: *Expression, allocator: *std.mem.Allocator) void {
        switch (self.*) {
            .number_constant => {},
            .variable_get => |*variable| {
                allocator.free(variable);
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

    pub fn deinit(self: *Statement, allocator: *std.mem.Allocator) void {
        switch (self.*) {
            .variable_decl => |*decl| {
                allocator.free(decl.name);
                decl.value.deinit(allocator);
            },
            .block => |*block| {
                block.deinit(allocator);
            }
        }
        allocator.destroy(self);
    }
};

pub const Block = struct {
    statements: std.ArrayList(*Statement),

    pub fn init(allocator: *std.mem.Allocator) Block {
        return Block{
            .statements = std.ArrayList(*Statement).init(allocator.*),
        };
    }

    pub fn deinit(self: *Block, allocator: *std.mem.Allocator) void {
        for (self.statements.items) |statement| {
            statement.deinit(allocator);
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

    pub fn deinit(self: *Parser) void {
        self.root.deinit(self.allocator);
    }

    pub fn parse(self: *Parser) ParseError!void {
        _ = self.nextToken();
        while (self.lexer.queue.len > 0) {
            const statement = try self.parseStatement();
            try self.root.statements.append(statement);
        }
    }

    fn parseExpression(self: *Parser) ParseError!*Expression {
        if (self.current == null) {
            return ParseError.UnexpectedEnd;
        }

        const expression = switch (self.current.?.tag) {
            .identifier => try self.parseVarGet(),
            .number => try self.parseNumberConstant(),
            else => return ParseError.UnexpectedToken,
        };

        return expression;
    }

    fn parseVarGet(self: *Parser) ParseError!*Expression {
        const identifier = try self.expectToken(.identifier);
        var expression = try self.allocator.create(Expression);
        errdefer self.allocator.destroy(expression);
        expression.variable_get = try self.allocator.dupe(u8, self.lexer.source[identifier.start..identifier.end]);
        return expression;
    }

    fn parseNumberConstant(self: *Parser) ParseError!*Expression {
        const number = try self.expectToken(.number);
        var expression = try self.allocator.create(Expression);
        expression.number_constant = std.fmt.parseInt(
            @TypeOf(expression.number_constant), 
            self.lexer.source[number.start..number.end],
            10,
        ) catch 0;
        return expression;
    }

    fn parseStatement(self: *Parser) ParseError!*Statement {
        if (self.current == null) {
            return ParseError.UnexpectedEnd;
        }

        const statement = switch (self.current.?.tag) {
            .keyword_var => try self.parseVarDecl(),
            else => return ParseError.UnexpectedToken,
        };
        errdefer statement.deinit(self.allocator);

        _ = try self.expectToken(.semicolon);

        return statement;
    }

    fn parseVarDecl(self: *Parser) ParseError!*Statement {
        _ = try self.expectToken(.keyword_var);
        const identifier = try self.expectToken(.identifier);
        _ = try self.expectToken(.equals);
        const expression = try self.parseExpression();
        var statement = try self.allocator.create(Statement);
        errdefer self.allocator.destroy(statement);
        statement.variable_decl = .{ 
            .name = try self.allocator.dupe(u8, self.lexer.source[identifier.start..identifier.end]),
            .value = expression,
        };
        return statement;
    }

    fn expectToken(self: *Parser, tag: lexer.TokenTag) ParseError!lexer.Token {
        if (self.current) |current| {
            if (current.tag == tag) {
                _ = self.nextToken();
                return current;
            } else {
                return ParseError.UnexpectedToken;
            }
        } else {
            return ParseError.UnexpectedToken;
        }
    }

    fn nextToken(self: *Parser) ?lexer.Token {
        self.previous = self.current;
        self.current = self.lexer.nextToken();
        return self.current;
    }
};
