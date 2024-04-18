const std = @import("std");
const ast = @import("ast.zig");
const err = @import("error.zig");
const lexer = @import("lexer.zig");
const types = @import("types.zig");

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEnd,
    UnterminatedBlock,
} || std.mem.Allocator.Error;

/// Parsing state, holds a reference to the lexer
/// and owns the AST
pub const Parser = struct {
    lexer: *lexer.Lexer,
    root: ast.AstNode,
    current: ?lexer.Token = null,
    previous: ?lexer.Token = null,
    err_ctx: *err.ErrorContext,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, lex: *lexer.Lexer) Parser {
        const parser = Parser{
            .lexer = lex,
            .root = ast.AstNode{ .index = 0, .data = .{ .block = .{
                .list = std.ArrayListUnmanaged(*ast.AstNode){},
            } } },
            .err_ctx = err_ctx,
            .allocator = allocator,
        };
        return parser;
    }

    pub fn deinit(self: *Parser) void {
        self.root.deinit(self.allocator);
    }

    /// Performs all parsing of the tokens held within the passed lexer
    pub fn parse(self: *Parser) ParseError!void {
        _ = self.nextToken();
        _ = self.nextToken();
        while (self.lexer.queue.len > 0) {
            const statement = try self.parseStatement();
            errdefer {
                statement.deinit(self.allocator);
                self.allocator.destroy(statement);
            }
            try self.root.data.block.list.append(self.allocator, statement);
        }
    }

    fn parseTypeDecl(self: *Parser) ParseError!types.Type {
        _ = try self.expectToken(.colon);
        const new_type = try self.parseType();
        return new_type;
    }

    fn parseType(self: *Parser) ParseError!types.Type {
        const name = try self.expectToken(.identifier);
        const raw_name = self.lexer.source[name.start..name.end];
        if (types.builtin_lookup.get(raw_name)) |builtin| {
            return builtin;
        }
        try self.err_ctx.errorFromToken(.unexpected_end, "Failed to parse type", .{}, name);
        return ParseError.UnexpectedToken;
    }

    fn parseExpression(self: *Parser) ParseError!*ast.AstNode {
        if (self.previous == null) {
            try self.err_ctx.newError(.unexpected_end, "Expected expression, found end", .{}, null);
            return ParseError.UnexpectedEnd;
        }

        const expression = switch (self.previous.?.tag) {
            .identifier => try self.parseVarGet(),
            .number => try self.parseNumberConstant(),
            else => {
                try self.err_ctx.errorFromToken(.unexpected_token, "Expected expression, found [{s},\"{s}\"]", .{ @tagName(self.previous.?.tag), self.lexer.source[self.previous.?.start..self.previous.?.end] }, self.previous.?);
                return ParseError.UnexpectedToken;
            },
        };

        return expression;
    }

    fn parseVarGet(self: *Parser) ParseError!*ast.AstNode {
        const identifier = try self.expectToken(.identifier);
        const expression = try self.allocator.create(ast.AstNode);
        errdefer self.allocator.destroy(expression);
        expression.* = .{
            .index = identifier.start,
            .data = .{
                .var_get = .{
                    .name = try self.allocator.dupe(u8, self.lexer.source[identifier.start..identifier.end]),
                },
            },
        };
        return expression;
    }

    fn parseNumberConstant(self: *Parser) ParseError!*ast.AstNode {
        const number = try self.expectToken(.number);
        const expression = try self.allocator.create(ast.AstNode);
        const value = std.fmt.parseInt(
            @TypeOf(expression.data.integer_constant.value),
            self.lexer.source[number.start..number.end],
            10,
        ) catch 0;
        expression.* = .{
            .index = number.start,
            .data = .{
                .integer_constant = .{
                    .value = value,
                },
            },
        };
        return expression;
    }

    fn parseStatement(self: *Parser) ParseError!*ast.AstNode {
        if (self.previous == null) {
            try self.err_ctx.newError(.unexpected_end, "Expected statement, found end", .{}, null);
            return ParseError.UnexpectedEnd;
        }

        var needs_semicolon = true;
        const statement = switch (self.previous.?.tag) {
            .keyword_var => try self.parseVarDecl(),
            .identifier => blk: {
                if (self.current) |current| {
                    switch (current.tag) {
                        .equals => break :blk try self.parseVarAssign(),
                        else => {},
                    }
                }
                break :blk try self.parseExpression();
            },
            .l_curly => blk: {
                needs_semicolon = false;
                break :blk try self.parseBlock();
            },
            else => try self.parseExpression(),
        };
        errdefer {
            statement.deinit(self.allocator);
            self.allocator.destroy(statement);
        }

        if (needs_semicolon) {
            _ = try self.expectToken(.semicolon);
        }

        return statement;
    }

    fn parseVarDecl(self: *Parser) ParseError!*ast.AstNode {
        _ = try self.expectToken(.keyword_var);

        const identifier = try self.expectToken(.identifier);
        var type_decl = try self.parseTypeDecl();
        errdefer type_decl.deinit(self.allocator);

        _ = try self.expectToken(.equals);

        const expression = try self.parseExpression();
        errdefer {
            expression.deinit(self.allocator);
            self.allocator.destroy(expression);
        }

        const statement = try self.allocator.create(ast.AstNode);
        errdefer self.allocator.destroy(statement);

        statement.* = .{ .index = identifier.start, .data = .{
            .var_decl = .{
                .name = try self.allocator.dupe(u8, self.lexer.source[identifier.start..identifier.end]),
                .decl_type = type_decl,
                .expr = expression,
            },
        } };

        return statement;
    }

    fn parseVarAssign(self: *Parser) ParseError!*ast.AstNode {
        const identifier = try self.expectToken(.identifier);

        _ = try self.expectToken(.equals);

        const expression = try self.parseExpression();
        errdefer {
            expression.deinit(self.allocator);
            self.allocator.destroy(expression);
        }

        const statement = try self.allocator.create(ast.AstNode);
        errdefer self.allocator.destroy(statement);

        statement.* = .{
            .index = identifier.start,
            .data = .{
                .var_assign = .{
                    .name = try self.allocator.dupe(u8, self.lexer.source[identifier.start..identifier.end]),
                    .expr = expression,
                },
            },
        };

        return statement;
    }

    fn parseBlock(self: *Parser) ParseError!*ast.AstNode {
        const start = try self.expectToken(.l_curly);

        var body = std.ArrayListUnmanaged(*ast.AstNode){};
        errdefer {
            for (body.items) |node| {
                node.deinit(self.allocator);
                self.allocator.destroy(node);
            }
            body.deinit(self.allocator);
        }

        const found_end = blk: {
            while (self.previous) |token| {
                if (token.tag == .r_curly) {
                    break :blk true;
                }

                const statement = try self.parseStatement();
                errdefer {
                    statement.deinit(self.allocator);
                    self.allocator.destroy(statement);
                }

                try body.append(self.allocator, statement);
            }
            break :blk false;
        };

        if (!found_end) {
            try self.err_ctx.newError(.unterminated_block, "Failed to find end of block", .{}, start.start);
            return ParseError.UnexpectedEnd;
        }

        _ = try self.expectToken(.r_curly);

        const block = try self.allocator.create(ast.AstNode);
        block.* = .{
            .index = start.start,
            .data = .{
                .block = .{
                    .list = body,
                },
            },
        };

        return block;
    }

    /// Errors if the current token doesn't have the passed tag.
    /// If it does, it runs nextToken and returns the token that matched
    /// the tag.
    fn expectToken(self: *Parser, tag: lexer.TokenTag) ParseError!lexer.Token {
        if (self.previous) |prev| {
            if (prev.tag == tag) {
                _ = self.nextToken();
                return prev;
            } else {
                try self.err_ctx.errorFromToken(.unexpected_token, "Expected token of type {s}, found [{s},\"{s}\"]", .{ @tagName(tag), @tagName(prev.tag), self.lexer.source[prev.start..prev.end] }, prev);
                return ParseError.UnexpectedToken;
            }
        } else {
            try self.err_ctx.newError(.unexpected_end, "Expected token of type {s}, found end", .{@tagName(tag)}, null);
            return ParseError.UnexpectedEnd;
        }
    }

    /// Puts the current token into previous, loads next token from
    /// lexer into current and returns the new current token
    fn nextToken(self: *Parser) ?lexer.Token {
        self.previous = self.current;
        self.current = self.lexer.nextToken();
        return self.previous;
    }
};
