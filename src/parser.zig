const std = @import("std");
const err = @import("error.zig");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const types = @import("types.zig");

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEnd,
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
            .root = ast.AstNode{ 
                .data = .{
                    .block = .{
                        .list = std.ArrayListUnmanaged(*ast.AstNode){},
                    }
                }
            },
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
        while (self.lexer.queue.len > 0) {
            const statement = try self.parseStatement();
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
        if (self.current == null) {
            try self.err_ctx.newError(.unexpected_end, "Expected expression, found end", .{}, null);
            return ParseError.UnexpectedEnd;
        }

        const expression = switch (self.current.?.tag) {
            .identifier => try self.parseVarGet(),
            .number => try self.parseNumberConstant(),
            else => {
                try self.err_ctx.errorFromToken(.unexpected_token, "Expected expression, found [{s},\"{s}\"]", 
                    .{@tagName(self.current.?.tag), self.lexer.source[self.current.?.start..self.current.?.end]}, self.current.?);
                return ParseError.UnexpectedToken;
            }
        };

        return expression;
    }

    fn parseVarGet(self: *Parser) ParseError!*ast.AstNode {
        const identifier = try self.expectToken(.identifier);
        const expression = try self.allocator.create(ast.AstNode);
        errdefer self.allocator.destroy(expression);
        expression.* = .{ 
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
            .data = .{ 
                .integer_constant = .{
                    .value = value,
                },
            },
        };
        return expression;
    }

    fn parseStatement(self: *Parser) ParseError!*ast.AstNode {
        if (self.current == null) {
            try self.err_ctx.newError(.unexpected_end, "Expected statement, found end", .{}, null);
            return ParseError.UnexpectedEnd;
        }

        const statement = switch (self.current.?.tag) {
            .keyword_var => try self.parseVarDecl(),
            else => return ParseError.UnexpectedToken,
        };
        errdefer { 
            statement.deinit(self.allocator);
            self.allocator.destroy(statement);
        }

        _ = try self.expectToken(.semicolon);

        return statement;
    }

    fn parseVarDecl(self: *Parser) ParseError!*ast.AstNode {
        _ = try self.expectToken(.keyword_var);

        const identifier = try self.expectToken(.identifier);
        var type_decl = try self.parseTypeDecl();
        errdefer type_decl.deinit(self.allocator);

        _ = try self.expectToken(.equals);

        const expression = try self.parseExpression();
        const statement = try self.allocator.create(ast.AstNode);
        errdefer self.allocator.destroy(statement);

        statement.* = .{ 
            .data = .{
                .var_decl = .{
                    .name = try self.allocator.dupe(u8, self.lexer.source[identifier.start..identifier.end]),
                    .decl_type = type_decl,
                    .expr = expression,
                },
            }
        };

        return statement;
    }
    
    /// Errors if the current token doesn't have the passed tag.
    /// If it does, it runs nextToken and returns the token that matched
    /// the tag.
    fn expectToken(self: *Parser, tag: lexer.TokenTag) ParseError!lexer.Token {
        if (self.current) |current| {
            if (current.tag == tag) {
                _ = self.nextToken();
                return current;
            } else {
                try self.err_ctx.errorFromToken(.unexpected_token, 
                    "Expected token of type {s}, found [{s},\"{s}\"]", 
                    .{@tagName(tag), @tagName(current.tag), self.lexer.source[current.start..current.end]}, 
                    current);
                return ParseError.UnexpectedToken;
            }
        } else {
            try self.err_ctx.newError(.unexpected_end,
                "Expected token of type {s}, found end",
                .{@tagName(tag)},
                null);
            return ParseError.UnexpectedEnd;
        }
    }
    
    /// Puts the current token into previous, loads next token from 
    /// lexer into current and returns the new current token
    fn nextToken(self: *Parser) ?lexer.Token {
        self.previous = self.current;
        self.current = self.lexer.nextToken();
        return self.current;
    }
};
