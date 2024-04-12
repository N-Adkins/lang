const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const types = @import("types.zig");

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEnd,
} || std.mem.Allocator.Error;

pub const Parser = struct {
    lexer: *lexer.Lexer,
    root: ast.Block,
    current_scope: *ast.Block,
    current: ?lexer.Token = null,
    previous: ?lexer.Token = null,
    allocator: std.mem.Allocator,

    pub fn init(lex: *lexer.Lexer, allocator: std.mem.Allocator) Parser {
        var parser = Parser{
            .lexer = lex,
            .root = ast.Block.init(null, allocator),
            .current_scope = undefined,
            .allocator = allocator,
        };
        parser.current_scope = &parser.root;
        return parser;
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

    fn parseTypeDecl(self: *Parser) ParseError!*types.Type {
        _ = try self.expectToken(.colon);
        const new_type = try self.parseType();
        return new_type;
    }

    fn parseType(self: *Parser) ParseError!*types.Type {
        const name = try self.expectToken(.identifier);
        const raw_name = self.lexer.source[name.start..name.end];
        if (types.builtin_lookup.has(raw_name)) {
            const new = try self.allocator.create(types.Type);
            new.* = types.builtin_lookup.get(raw_name).?;
            return new;
        }

        // parse custom types w/ recursive descent for function
        // types
        return ParseError.UnexpectedToken;
    }

    fn parseExpression(self: *Parser) ParseError!*ast.Expression {
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

    fn parseVarGet(self: *Parser) ParseError!*ast.Expression {
        const identifier = try self.expectToken(.identifier);
        const expression = try self.allocator.create(ast.Expression);
        errdefer self.allocator.destroy(expression);
        expression.* = .{ .variable_get = try self.allocator.dupe(u8, self.lexer.source[identifier.start..identifier.end]) };
        return expression;
    }

    fn parseNumberConstant(self: *Parser) ParseError!*ast.Expression {
        const number = try self.expectToken(.number);
        const expression = try self.allocator.create(ast.Expression);
        expression.* = .{
            .number_constant = std.fmt.parseInt(
                @TypeOf(expression.number_constant),
                self.lexer.source[number.start..number.end],
                10,
            ) catch 0,
        };
        return expression;
    }

    fn parseStatement(self: *Parser) ParseError!*ast.Statement {
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

    fn parseVarDecl(self: *Parser) ParseError!*ast.Statement {
        _ = try self.expectToken(.keyword_var);

        const identifier = try self.expectToken(.identifier);
        const type_decl = try self.parseTypeDecl();
        errdefer type_decl.deinit(self.allocator);

        _ = try self.expectToken(.equals);

        const expression = try self.parseExpression();
        const statement = try self.allocator.create(ast.Statement);
        errdefer self.allocator.destroy(statement);

        statement.* = .{ .variable_decl = .{
            .name = try self.allocator.dupe(u8, self.lexer.source[identifier.start..identifier.end]),
            .decl_type = type_decl,
            .value = expression,
        } };

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
