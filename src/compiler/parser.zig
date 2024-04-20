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
        while (self.previous != null) {
            const statement = try self.parseStatement();
            errdefer {
                statement.deinit(self.allocator);
                self.allocator.destroy(statement);
            }
            try self.root.data.block.list.append(self.allocator, statement);
        }
    }

    fn parseType(self: *Parser) Error!types.Type {
        if (self.previous == null) {
            try self.err_ctx.newError(.unexpected_end, "Expected type, found end", .{}, null);
            return Error.UnexpectedEnd;
        }

        switch (self.previous.?.tag) {
            .identifier => {
                const name = try self.expectToken(.identifier);
                const raw_name = self.lexer.source[name.start..name.end];
                if (types.builtin_lookup.get(raw_name)) |builtin| {
                    return builtin;
                }
                try self.err_ctx.errorFromToken(.unexpected_end, "Failed to parse type \"{s}\"", .{raw_name}, name);
                return Error.UnexpectedToken;
            },
            .keyword_fn => {
                _ = self.nextToken();
                _ = try self.expectToken(.l_paren);

                var arg_types = std.ArrayListUnmanaged(types.Type){};
                errdefer {
                    for (arg_types.items) |*arg| {
                        arg.deinit(self.allocator);
                    }
                    arg_types.deinit(self.allocator);
                }

                while (self.previous != null and self.previous.?.tag != .r_paren) {
                    try arg_types.append(self.allocator, try self.parseType());
                    if (self.previous != null and self.previous.?.tag != .r_paren) {
                        _ = try self.expectToken(.comma);
                    }
                }

                _ = try self.expectToken(.r_paren);
                _ = try self.expectToken(.right_arrow);

                const ret_type_raw = try self.parseType();
                const ret_type = try self.allocator.create(types.Type);
                ret_type.* = ret_type_raw;

                return types.Type{
                    .function = .{
                        .args = arg_types,
                        .ret = ret_type,
                    },
                };
            },
            else => {
                try self.err_ctx.errorFromToken(.unexpected_end, "Failed to parse type", .{}, self.previous.?);
                return Error.UnexpectedToken;
            },
        }
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
                .l_paren => ast.Operator{ .call = undefined },
                else => break,
            };

            if (postfixPrecedence(op)) |precedence| {
                if (precedence.lhs < min_precedence) {
                    break;
                }
                _ = self.nextToken();
                const node = try self.parsePostfix(op, lhs);
                lhs = node;
                continue;
            }

            if (infixPrecedence(op)) |precedence| {
                if (precedence.lhs < min_precedence) {
                    break;
                }
                _ = self.nextToken();
                const rhs = try self.parsePrecedenceExpression(precedence.rhs);
                errdefer {
                    rhs.deinit(self.allocator);
                    self.allocator.destroy(rhs);
                }

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
                continue;
            }
        }

        return lhs;
    }

    fn parseBasicExpression(self: *Parser) Error!*ast.Node {
        const expression = switch (self.previous.?.tag) {
            .l_paren => try self.parseParen(),
            .identifier => try self.parseVarGet(),
            .number => try self.parseNumberConstant(),
            .keyword_fn => try self.parseFunctionDecl(),
            else => {
                try self.err_ctx.errorFromToken(.unexpected_token, "Expected expression, found [{s},\"{s}\"]", .{ @tagName(self.previous.?.tag), self.lexer.source[self.previous.?.start..self.previous.?.end] }, self.previous.?);
                return Error.UnexpectedToken;
            },
        };
        return expression;
    }

    fn parsePostfix(self: *Parser, op: ast.Operator, expr: *ast.Node) Error!*ast.Node {
        const node = try self.allocator.create(ast.Node);
        errdefer self.allocator.destroy(node);
        node.index = expr.index;
        switch (op) {
            .call => |_| {
                var args = std.ArrayListUnmanaged(*ast.Node){};
                errdefer args.deinit(self.allocator);

                while (self.previous != null and self.previous.?.tag != .r_paren) {
                    const arg = try self.parseExpression();
                    errdefer {
                        arg.deinit(self.allocator);
                        self.allocator.destroy(arg);
                    }

                    try args.append(self.allocator, arg);

                    if (self.previous != null and self.previous.?.tag == .comma) {
                        _ = self.nextToken();
                    }
                }
                _ = try self.expectToken(.r_paren);
                node.data = .{ .unary_op = .{
                    .op = .{
                        .call = .{
                            .args = args,
                        },
                    },
                    .expr = expr,
                } };
            },
            else => unreachable,
        }
        return node;
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

    fn parseFunctionDecl(self: *Parser) Error!*ast.Node {
        const start = try self.expectToken(.keyword_fn);
        _ = try self.expectToken(.l_paren);

        var args = std.ArrayListUnmanaged(ast.SymbolDecl){};
        errdefer {
            for (args.items) |*arg| {
                arg.deinit(self.allocator);
            }
            args.deinit(self.allocator);
        }

        while (self.previous != null and self.previous.?.tag != .r_paren) {
            const name = try self.expectToken(.identifier);

            _ = try self.expectToken(.colon);

            var arg_type = try self.parseType();
            errdefer arg_type.deinit(self.allocator);

            if (arg_type.equal(&.void)) {
                try self.err_ctx.newError(.unexpected_token, "Void is a not a permitted argument type", .{}, name.end);
                return Error.UnexpectedToken;
            }

            try args.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, self.lexer.source[name.start..name.end]),
                .decl_type = arg_type,
            });

            if (self.previous != null and self.previous.?.tag == .comma) {
                _ = self.nextToken();
            }
        }

        _ = try self.expectToken(.r_paren);
        _ = try self.expectToken(.right_arrow);

        const ret_type = try self.parseType();
        const body = try self.parseBlock();

        const node = try self.allocator.create(ast.Node);
        node.* = .{
            .index = start.start,
            .data = .{
                .function_decl = .{
                    .args = args,
                    .ret_type = ret_type,
                    .body = body,
                },
            },
        };

        return node;
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
            .keyword_return => try self.parseReturn(),
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

        const next = try self.expectToken(null);

        var maybe_type_decl: ?types.Type = switch (next.tag) {
            .colon => blk: {
                const decl = try self.parseType();
                if (decl.equal(&.void)) {
                    try self.err_ctx.errorFromToken(.unexpected_token, "Void is a not a permitted variable type", .{}, next);
                    return Error.UnexpectedToken;
                }
                _ = try self.expectToken(.equals);
                break :blk decl;
            },
            .colon_equals => null,
            else => {
                try self.err_ctx.errorFromToken(.unexpected_token, "Expected ':' or ':=', found \"{s}\"", .{self.lexer.source[next.start..next.end]}, next);
                return Error.UnexpectedToken;
            },
        };
        errdefer {
            if (maybe_type_decl) |*decl| {
                decl.deinit(self.allocator);
            }
        }

        const expression = try self.parseExpression();
        errdefer {
            expression.deinit(self.allocator);
            self.allocator.destroy(expression);
        }

        const statement = try self.allocator.create(ast.Node);
        errdefer self.allocator.destroy(statement);

        statement.* = .{ .index = identifier.start, .data = .{
            .var_decl = .{
                .symbol = .{
                    .name = try self.allocator.dupe(u8, self.lexer.source[identifier.start..identifier.end]),
                    .decl_type = maybe_type_decl,
                },
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

    fn parseReturn(self: *Parser) Error!*ast.Node {
        const start = try self.expectToken(.keyword_return);
        if (self.previous) |prev| {
            const expr: ?*ast.Node = switch (prev.tag) {
                .semicolon => null,
                else => try self.parseExpression(),
            };
            errdefer {
                if (expr) |expr_ptr| {
                    expr_ptr.deinit(self.allocator);
                    self.allocator.destroy(expr_ptr);
                }
            }
            const node = try self.allocator.create(ast.Node);
            node.* = .{
                .index = start.start,
                .data = .{
                    .return_stmt = .{
                        .expr = expr,
                    },
                },
            };
            return node;
        } else {
            try self.err_ctx.errorFromToken(.unexpected_token, "Expected expression or ';' after return keyword, found end", .{}, start);
            return Error.UnexpectedToken;
        }
    }

    /// Errors if the current token doesn't have the passed tag.
    /// If it does, it runs nextToken and returns the token that matched
    /// the tag.
    fn expectToken(self: *Parser, maybe_tag: ?lexer.TokenTag) Error!lexer.Token {
        if (maybe_tag) |tag| {
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
        } else {
            if (self.previous) |prev| {
                _ = self.nextToken();
                return prev;
            } else {
                try self.err_ctx.newError(.unexpected_end, "Expected any token, found end", .{}, null);
                return Error.UnexpectedEnd;
            }
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
            else => null,
        };
    }

    fn postfixPrecedence(op: ast.Operator) ?Precedence {
        return switch (op) {
            .call => .{ .lhs = 7, .rhs = 0 },
            else => null,
        };
    }
};
