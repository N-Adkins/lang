//! Parsing Pass, handles turning tokens into an AST

const std = @import("std");
const ast = @import("ast.zig");
const err = @import("error.zig");
const lexer = @import("lexer.zig");
const types = @import("types.zig");

/// Container for the precedence of an operator
const Precedence = struct {
    lhs: usize,
    rhs: usize,
};

pub const Error = error{
    UnexpectedToken,
    UnexpectedEnd,
    UnterminatedBlock,
} || std.mem.Allocator.Error;

/// Parsing state, holds a reference to the lexer and owns the AST
pub const Parser = struct {
    lexer: *lexer.Lexer,
    root: ast.Node,
    current: ?lexer.Token = null,
    previous: ?lexer.Token = null,
    err_ctx: *err.ErrorContext,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, lex: *lexer.Lexer) Parser {
        const parser = Parser{
            .lexer = lex,
            .root = ast.Node{ .index = 0, .data = .{ .block = .{
                .list = std.ArrayListUnmanaged(*ast.Node){},
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
    pub fn parse(self: *Parser) Error!void {
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

    fn parseTypeDecl(self: *Parser) Error!types.Type {
        _ = try self.expectToken(.colon);
        const new_type = try self.parseType();
        return new_type;
    }

    fn parseType(self: *Parser) Error!types.Type {
        const name = try self.expectToken(.identifier);
        const raw_name = self.lexer.source[name.start..name.end];
        if (types.builtin_lookup.get(raw_name)) |builtin| {
            return builtin;
        }
        try self.err_ctx.errorFromToken(.unexpected_end, "Failed to parse type", .{}, name);
        return Error.UnexpectedToken;
    }

    fn parseExpression(self: *Parser) Error!*ast.Node {
        if (self.previous == null) {
            try self.err_ctx.newError(.unexpected_end, "Expected expression, found end", .{}, null);
            return Error.UnexpectedEnd;
        }
        return try self.parsePrecedenceExpression(0);
    }

    /// Pratt parser function for expressions
    fn parsePrecedenceExpression(self: *Parser, min_precedence: usize) Error!*ast.Node {
        var lhs = try self.parseBasicExpression();
        errdefer {
            lhs.deinit(self.allocator);
            self.allocator.destroy(lhs);
        }

        // binary expressions
        while (self.previous) |prev| {
            const index = prev.start;
            const op = switch (prev.tag) {
                .plus => ast.Operator.add,
                .minus => ast.Operator.sub,
                .star => ast.Operator.mul,
                .slash => ast.Operator.div,
                else => break,
            };

            const precedence = infixPrecedence(op).?;
            if (precedence.lhs < min_precedence) {
                break;
            }

            _ = self.nextToken();
            const rhs = try self.parsePrecedenceExpression(precedence.rhs);

            const node = try self.allocator.create(ast.Node);
            node.* = .{
                .index = index,
                .data = .{
                    .binary_op = .{
                        .op = op,
                        .lhs = lhs,
                        .rhs = rhs,
                    },
                },
            };

            lhs = node;
        }

        return lhs;
    }

    fn parseBasicExpression(self: *Parser) Error!*ast.Node {
        const expression = switch (self.previous.?.tag) {
            .l_paren => try self.parseParen(),
            .identifier => try self.parseVarGet(),
            .number => try self.parseNumberConstant(),
            else => {
                try self.err_ctx.errorFromToken(.unexpected_token, "Expected expression, found [{s},\"{s}\"]", .{ @tagName(self.previous.?.tag), self.lexer.source[self.previous.?.start..self.previous.?.end] }, self.previous.?);
                return Error.UnexpectedToken;
            },
        };
        return expression;
    }

    fn parseParen(self: *Parser) Error!*ast.Node {
        _ = try self.expectToken(.l_paren);
        const expr = try self.parseExpression();
        _ = try self.expectToken(.r_paren);
        return expr;
    }

    fn parseVarGet(self: *Parser) Error!*ast.Node {
        const identifier = try self.expectToken(.identifier);
        const expression = try self.allocator.create(ast.Node);
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

    fn parseNumberConstant(self: *Parser) Error!*ast.Node {
        const number = try self.expectToken(.number);
        const expression = try self.allocator.create(ast.Node);
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

    fn parseStatement(self: *Parser) Error!*ast.Node {
        if (self.previous == null) {
            try self.err_ctx.newError(.unexpected_end, "Expected statement, found end", .{}, null);
            return Error.UnexpectedEnd;
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

    fn parseVarDecl(self: *Parser) Error!*ast.Node {
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

        const statement = try self.allocator.create(ast.Node);
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

    fn parseVarAssign(self: *Parser) Error!*ast.Node {
        const identifier = try self.expectToken(.identifier);

        _ = try self.expectToken(.equals);

        const expression = try self.parseExpression();
        errdefer {
            expression.deinit(self.allocator);
            self.allocator.destroy(expression);
        }

        const statement = try self.allocator.create(ast.Node);
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

    fn parseBlock(self: *Parser) Error!*ast.Node {
        const start = try self.expectToken(.l_curly);

        var body = std.ArrayListUnmanaged(*ast.Node){};
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
            return Error.UnexpectedEnd;
        }

        _ = try self.expectToken(.r_curly);

        const block = try self.allocator.create(ast.Node);
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
    fn expectToken(self: *Parser, tag: lexer.TokenTag) Error!lexer.Token {
        if (self.previous) |prev| {
            if (prev.tag == tag) {
                _ = self.nextToken();
                return prev;
            } else {
                try self.err_ctx.errorFromToken(.unexpected_token, "Expected token of type {s}, found [{s},\"{s}\"]", .{ @tagName(tag), @tagName(prev.tag), self.lexer.source[prev.start..prev.end] }, prev);
                return Error.UnexpectedToken;
            }
        } else {
            try self.err_ctx.newError(.unexpected_end, "Expected token of type {s}, found end", .{@tagName(tag)}, null);
            return Error.UnexpectedEnd;
        }
    }

    /// Puts the current token into previous, loads next token from
    /// lexer into current and returns the new current token
    fn nextToken(self: *Parser) ?lexer.Token {
        self.previous = self.current;
        self.current = self.lexer.nextToken();
        return self.previous;
    }

    fn infixPrecedence(op: ast.Operator) ?Precedence {
        return switch (op) {
            .add, .sub => .{ .lhs = 1, .rhs = 2 },
            .mul, .div => .{ .lhs = 3, .rhs = 4 },
        };
    }
};
