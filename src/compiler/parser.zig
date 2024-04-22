//! Parsing Pass, handles turning tokens into an AST

const std = @import("std");
const ast = @import("ast.zig");
const builtin = @import("builtin.zig");
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

    /// Performs all parsing of the tokens held within the passed lexer
    pub fn parse(self: *Parser) Error!void {
        _ = self.nextToken();
        _ = self.nextToken();
        while (self.previous != null) {
            const statement = try self.parseStatement();
            try self.root.data.block.list.append(self.allocator, statement);
        }
    }

    fn parseType(self: *Parser) Error!types.Type {
        if (self.previous == null) {
            try self.err_ctx.newError(.unexpected_end, "Expected type, found end", .{}, null);
            return Error.UnexpectedEnd;
        }

        switch (self.previous.?.tag) {
            .l_square => {
                _ = self.nextToken();
                const inner = try self.parseType();
                _ = try self.expectToken(.r_square);
                const heap_inner = try self.allocator.create(types.Type);
                heap_inner.* = inner;
                return types.Type{ .array = .{ .base = heap_inner } };
            },
            .identifier => {
                const name = try self.expectToken(.identifier);
                const raw_name = self.lexer.source[name.start..name.end];
                if (types.builtin_lookup.get(raw_name)) |builtin_type| {
                    return builtin_type;
                }
                try self.err_ctx.errorFromToken(.unexpected_end, "Failed to parse type \"{s}\"", .{raw_name}, name);
                return Error.UnexpectedToken;
            },
            .keyword_fn => {
                _ = self.nextToken();
                _ = try self.expectToken(.l_paren);

                var arg_types = std.ArrayListUnmanaged(types.Type){};

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

        // binary expressions
        while (self.previous) |prev| {
            const index = prev.start;
            const op = switch (prev.tag) {
                .plus => ast.Operator.add,
                .minus => ast.Operator.sub,
                .star => ast.Operator.mul,
                .slash => ast.Operator.div,
                .l_paren => ast.Operator{ .call = undefined },
                .l_square => ast.Operator{ .index = undefined },
                .equals_equals => ast.Operator.equals,
                .bang_equals => ast.Operator.not_equals,
                .keyword_and => ast.Operator.boolean_and,
                .keyword_or => ast.Operator.boolean_or,
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
            .l_square => try self.parseArrayInit(),
            .identifier => blk: {
                if (builtin.lookup.has(self.lexer.source[self.previous.?.start..self.previous.?.end])) {
                    break :blk try self.parseBuiltin();
                }
                break :blk try self.parseVarGet();
            },
            .number => try self.parseNumberConstant(),
            .string_literal => try self.parseStringConstant(),
            .keyword_fn => try self.parseFunctionDecl(),
            .keyword_true, .keyword_false => try self.parseBoolean(),
            else => {
                try self.err_ctx.errorFromToken(.unexpected_token, "Expected expression, found [{s},\"{s}\"]", .{ @tagName(self.previous.?.tag), self.lexer.source[self.previous.?.start..self.previous.?.end] }, self.previous.?);
                return Error.UnexpectedToken;
            },
        };
        return expression;
    }

    fn parsePostfix(self: *Parser, op: ast.Operator, expr: *ast.Node) Error!*ast.Node {
        const node = try self.allocator.create(ast.Node);
        node.index = expr.index;

        switch (op) {
            .call => |_| {
                var args = std.ArrayListUnmanaged(*ast.Node){};

                while (self.previous != null and self.previous.?.tag != .r_paren) {
                    const arg = try self.parseExpression();
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
            .index => |_| {
                node.data = .{
                    .unary_op = .{
                        .op = .{
                            .index = .{
                                .index = try self.parseExpression(),
                            },
                        },
                        .expr = expr,
                    },
                };
                _ = try self.expectToken(.r_square);
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

    fn parseArrayInit(self: *Parser) Error!*ast.Node {
        const start = try self.expectToken(.l_square);

        var items = std.ArrayListUnmanaged(*ast.Node){};

        while (self.previous != null and self.previous.?.tag != .r_square) {
            const expr = try self.parseExpression();
            try items.append(self.allocator, expr);
            if (self.previous != null and self.previous.?.tag == .comma) {
                _ = self.nextToken();
            }
        }

        _ = try self.expectToken(.r_square);

        const node = try self.allocator.create(ast.Node);
        node.* = .{
            .index = start.start,
            .data = .{
                .array_init = .{
                    .items = items,
                },
            },
        };

        return node;
    }

    fn parseBuiltin(self: *Parser) Error!*ast.Node {
        const identifier = try self.expectToken(.identifier);
        const idx: u8 = @truncate(builtin.lookup.getIndex(self.lexer.source[identifier.start..identifier.end]).?);
        const data: builtin.Data = builtin.lookup.kvs[idx].value;

        _ = try self.expectToken(.l_paren);

        const args = try self.allocator.alloc(*ast.Node, data.arg_count);

        for (0..data.arg_count) |i| {
            args[i] = try self.parseExpression();
            if (i < data.arg_count - 1) {
                _ = try self.expectToken(.comma);
            }
        }

        _ = try self.expectToken(.r_paren);

        const node = try self.allocator.create(ast.Node);
        node.* = .{
            .index = identifier.start,
            .data = .{
                .builtin_call = .{
                    .idx = idx,
                    .args = args,
                },
            },
        };

        return node;
    }

    fn parseVarGet(self: *Parser) Error!*ast.Node {
        const identifier = try self.expectToken(.identifier);
        const expression = try self.allocator.create(ast.Node);

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
        const value = std.fmt.parseFloat(
            @TypeOf(expression.data.number_constant.value),
            self.lexer.source[number.start..number.end],
        ) catch 0.0;
        expression.* = .{
            .index = number.start,
            .data = .{
                .number_constant = .{
                    .value = value,
                },
            },
        };
        return expression;
    }

    fn parseStringConstant(self: *Parser) Error!*ast.Node {
        const string = try self.expectToken(.string_literal);
        const node = try self.allocator.create(ast.Node);
        node.* = .{
            .index = string.start,
            .data = .{
                .string_constant = .{
                    .raw = try self.allocator.dupe(u8, self.lexer.source[string.start..string.end]),
                },
            },
        };
        return node;
    }

    fn parseFunctionDecl(self: *Parser) Error!*ast.Node {
        const start = try self.expectToken(.keyword_fn);
        _ = try self.expectToken(.l_paren);

        var args = std.ArrayListUnmanaged(ast.SymbolDecl){};

        while (self.previous != null and self.previous.?.tag != .r_paren) {
            const name = try self.expectToken(.identifier);

            _ = try self.expectToken(.colon);

            var arg_type = try self.parseType();

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

    fn parseBoolean(self: *Parser) Error!*ast.Node {
        const token = try self.expectToken(null);

        const value = if (token.tag == .keyword_true) true else if (token.tag == .keyword_false) false else unreachable;

        const node = try self.allocator.create(ast.Node);
        node.* = .{
            .index = token.start,
            .data = .{
                .boolean_constant = .{
                    .value = value,
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
                const expr = try self.parseExpression();
                switch (expr.data) {
                    .unary_op => |unary| {
                        switch (unary.op) {
                            .index => |_| {
                                if (self.previous != null and self.previous.?.tag == .equals) {
                                    break :blk try self.parseArraySet(expr);
                                }
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
                break :blk expr;
            },
            .l_curly => blk: {
                needs_semicolon = false;
                break :blk try self.parseBlock();
            },
            .keyword_if => blk: {
                needs_semicolon = false;
                break :blk try self.parseIf();
            },
            .keyword_return => try self.parseReturn(),
            else => blk: {
                const expr = try self.parseExpression();
                switch (expr.data) {
                    .unary_op => |unary| {
                        switch (unary.op) {
                            .index => |_| {
                                if (self.previous != null and self.previous.?.tag == .equals) {
                                    break :blk try self.parseArraySet(expr);
                                }
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
                break :blk expr;
            },
        };

        if (needs_semicolon) {
            _ = try self.expectToken(.semicolon);
        }

        return statement;
    }

    fn parseVarDecl(self: *Parser) Error!*ast.Node {
        _ = try self.expectToken(.keyword_var);

        const identifier = try self.expectToken(.identifier);

        const next = try self.expectToken(null);

        const maybe_type_decl: ?types.Type = switch (next.tag) {
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

        const expression = try self.parseExpression();
        const statement = try self.allocator.create(ast.Node);

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
        const statement = try self.allocator.create(ast.Node);

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

        const found_end = blk: {
            while (self.previous) |token| {
                if (token.tag == .r_curly) {
                    break :blk true;
                }
                const statement = try self.parseStatement();
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

    fn parseIf(self: *Parser) Error!*ast.Node {
        const if_start = try self.expectToken(.keyword_if);
        const expr = try self.parseExpression();
        const true_body = try self.parseBlock();
        const false_body: ?*ast.Node =
            if (self.previous != null and self.previous.?.tag == .keyword_else)
        blk: {
            _ = self.nextToken();
            break :blk try self.parseBlock();
        } else null;
        const node = try self.allocator.create(ast.Node);
        node.* = .{
            .index = if_start.start,
            .data = .{
                .if_stmt = .{
                    .expr = expr,
                    .true_body = true_body,
                    .false_body = false_body,
                },
            },
        };
        return node;
    }

    fn parseReturn(self: *Parser) Error!*ast.Node {
        const start = try self.expectToken(.keyword_return);
        if (self.previous) |prev| {
            const expr: ?*ast.Node = switch (prev.tag) {
                .semicolon => null,
                else => try self.parseExpression(),
            };
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

    pub fn parseArraySet(self: *Parser, array_get: *ast.Node) Error!*ast.Node {
        const array = array_get.data.unary_op.expr;
        const index = array_get.data.unary_op.op.index.index;
        _ = try self.expectToken(.equals);
        const expr = try self.parseExpression();
        const node = try self.allocator.create(ast.Node);
        node.* = .{
            .index = array.index,
            .data = .{
                .array_set = .{
                    .array = array,
                    .index = index,
                    .expr = expr,
                },
            },
        };
        return node;
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
            .add, .sub => .{ .lhs = 10, .rhs = 11 },
            .mul, .div => .{ .lhs = 12, .rhs = 13 },
            .equals, .not_equals => .{ .lhs = 5, .rhs = 6 },
            .boolean_and, .boolean_or => .{ .lhs = 2, .rhs = 3 },
            else => null,
        };
    }

    fn postfixPrecedence(op: ast.Operator) ?Precedence {
        return switch (op) {
            .call => .{ .lhs = 20, .rhs = 0 },
            .index => .{ .lhs = 20, .rhs = 0 },
            else => null,
        };
    }
};
