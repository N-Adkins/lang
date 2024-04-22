//! Lexing Pass, handles turning source code into tokens

const std = @import("std");
const err = @import("error.zig");

pub const TokenTag = enum {
    identifier,
    number,
    string_literal,
    l_paren,
    r_paren,
    l_curly,
    r_curly,
    comma,
    period,
    semicolon,
    colon,
    colon_equals,
    right_arrow,
    bang,
    bang_equals,
    minus,
    minus_minus,
    minus_equals,
    plus,
    plus_plus,
    plus_equals,
    star,
    star_equals,
    slash,
    slash_equals,
    equals,
    equals_equals,
    less_than,
    less_than_equals,
    greater_than,
    greater_than_equals,
    keyword_var,
    keyword_if,
    keyword_else,
    keyword_fn,
    keyword_return,
    keyword_true,
    keyword_false,
    keyword_and,
    keyword_or,
};

/// Used when parsing identifiers
const keyword_lookup = std.ComptimeStringMap(TokenTag, .{
    .{ "var", TokenTag.keyword_var },
    .{ "if", TokenTag.keyword_if },
    .{ "else", TokenTag.keyword_else },
    .{ "fn", TokenTag.keyword_fn },
    .{ "return", TokenTag.keyword_return },
    .{ "false", TokenTag.keyword_false },
    .{ "true", TokenTag.keyword_true },
    .{ "and", TokenTag.keyword_and },
    .{ "or", TokenTag.keyword_or },
});

pub const Token = struct {
    tag: TokenTag,
    start: usize,
    end: usize,
};

pub const Error = error{
    UnexpectedCharacter,
    UnterminatedString,
} || std.mem.Allocator.Error;

/// Lexer pass, pre-generates all tokens into a queue and feeds them back. It is not
/// incrementally tokenized.
pub const Lexer = struct {
    source: []const u8,
    index: usize = 0,
    queue: std.DoublyLinkedList(Token) = .{},
    err_ctx: *err.ErrorContext,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, source: []const u8) Lexer {
        return Lexer{
            .source = source,
            .err_ctx = err_ctx,
            .allocator = allocator,
        };
    }

    /// Returns most recent token
    pub fn peekToken(self: *Lexer) ?*Token {
        if (self.queue.first) |node| {
            return &node.data;
        }
        return null;
    }

    /// Pops token off of queue and returns it
    pub fn nextToken(self: *Lexer) ?Token {
        if (self.queue.popFirst()) |node| {
            const token = node.data;
            self.allocator.destroy(node);
            return token;
        }
        return null;
    }

    /// Queues all tokens in the contained source
    pub fn tokenize(self: *Lexer) Error!void {
        while (self.index < self.source.len) {
            self.skipWhitespace();
            if (self.peekChar() == null) {
                break;
            }
            try self.tokenizeNext();
        }
    }

    fn tokenizeNext(self: *Lexer) Error!void {
        std.debug.assert(self.peekChar() != null);
        const next = self.peekChar().?;
        if (isNumber(next)) {
            try self.tokenizeNumber();
        } else if (isIdentifier(next)) {
            try self.tokenizeIdentifier();
        } else if (next == '\"') {
            try self.tokenizeString();
        } else {
            try self.tokenizeSpecial();
        }
    }

    fn tokenizeNumber(self: *Lexer) Error!void {
        std.debug.assert(self.peekChar() != null);
        std.debug.assert(isNumber(self.peekChar().?));
        const start = self.index;
        while (self.peekChar()) |c| {
            if (!isNumber(c)) {
                break;
            }
            _ = self.nextChar();
        }
        const end = self.index;
        try self.pushToken(Token{ .tag = .number, .start = start, .end = end });
    }

    fn tokenizeIdentifier(self: *Lexer) Error!void {
        std.debug.assert(self.peekChar() != null);
        std.debug.assert(isIdentifier(self.peekChar().?));
        const start = self.index;
        while (self.peekChar()) |c| {
            if (!isIdentifier(c)) {
                break;
            }
            _ = self.nextChar();
        }
        const end = self.index;
        const tag = if (keyword_lookup.get(self.source[start..end])) |keyword| keyword else TokenTag.identifier;
        try self.pushToken(Token{ .tag = tag, .start = start, .end = end });
    }

    fn tokenizeString(self: *Lexer) Error!void {
        const start_char = self.nextChar().?;
        std.debug.assert(start_char == '\"');

        const start = self.index;
        while (self.peekChar()) |c| {
            _ = self.nextChar();
            if (c == '\"') {
                break;
            }
        }
        const end = self.index;

        if (end >= self.source.len - 1) {
            try self.err_ctx.newError(.unterminated_string, "Unterminated string literal", .{}, start - 1);
            return Error.UnexpectedCharacter;
        }

        try self.pushToken(Token{ .tag = .string_literal, .start = start, .end = end - 1 });
    }

    fn tokenizeSpecial(self: *Lexer) Error!void {
        std.debug.assert(self.peekChar() != null);
        const start = self.index;
        const char = self.nextChar().?;
        var tag: TokenTag = undefined;
        switch (char) {
            '(' => tag = .l_paren,
            ')' => tag = .r_paren,
            '{' => tag = .l_curly,
            '}' => tag = .r_curly,
            ',' => tag = .comma,
            '.' => tag = .period,
            '!' => if (self.peekChar()) |c| {
                switch (c) {
                    '=' => {
                        _ = self.nextChar();
                        tag = .bang_equals;
                    },
                    else => tag = .bang,
                }
            },
            '+' => if (self.peekChar()) |c| {
                switch (c) {
                    '+' => {
                        _ = self.nextChar();
                        tag = .plus_plus;
                    },
                    '=' => {
                        _ = self.nextChar();
                        tag = .plus_equals;
                    },
                    else => tag = .plus,
                }
            },
            '-' => if (self.peekChar()) |c| {
                switch (c) {
                    '-' => {
                        _ = self.nextChar();
                        tag = .minus_minus;
                    },
                    '>' => {
                        _ = self.nextChar();
                        tag = .right_arrow;
                    },
                    '=' => {
                        _ = self.nextChar();
                        tag = .minus_equals;
                    },
                    else => tag = .minus,
                }
            },
            '*' => if (self.peekChar()) |c| {
                switch (c) {
                    '=' => {
                        _ = self.nextChar();
                        tag = .star_equals;
                    },
                    else => tag = .star,
                }
            },
            '/' => if (self.peekChar()) |c| {
                switch (c) {
                    '=' => {
                        _ = self.nextChar();
                        tag = .slash_equals;
                    },
                    '/' => {
                        _ = self.nextChar();
                        self.ignoreLine();
                        return;
                    },
                    else => tag = .slash,
                }
            },
            '=' => if (self.peekChar()) |c| {
                switch (c) {
                    '=' => {
                        _ = self.nextChar();
                        tag = .equals_equals;
                    },
                    else => tag = .equals,
                }
            },
            '<' => if (self.peekChar()) |c| {
                switch (c) {
                    '=' => {
                        _ = self.nextChar();
                        tag = .less_than_equals;
                    },
                    else => tag = .less_than,
                }
            },
            '>' => if (self.peekChar()) |c| {
                switch (c) {
                    '=' => {
                        _ = self.nextChar();
                        tag = .greater_than_equals;
                    },
                    else => tag = .greater_than,
                }
            },
            ':' => if (self.peekChar()) |c| {
                switch (c) {
                    '=' => {
                        _ = self.nextChar();
                        tag = .colon_equals;
                    },
                    else => tag = .colon,
                }
            },
            ';' => tag = .semicolon,
            else => {
                try self.err_ctx.newError(.unexpected_character, "Unexpected character: '{c}'", .{char}, start);
                return Error.UnexpectedCharacter;
            },
        }
        const end = self.index;
        try self.pushToken(Token{ .tag = tag, .start = start, .end = end });
    }

    fn ignoreLine(self: *Lexer) void {
        while (self.nextChar()) |c| {
            if (c == '\n') {
                break;
            }
        }
    }

    fn pushToken(self: *Lexer, token: Token) Error!void {
        const node = try self.allocator.create(std.DoublyLinkedList(Token).Node);
        node.* = .{ .prev = null, .next = null, .data = token };
        self.queue.append(node);
    }

    fn peekChar(self: *Lexer) ?u8 {
        if (self.index >= self.source.len) {
            return null;
        }
        return self.source[self.index];
    }

    fn nextChar(self: *Lexer) ?u8 {
        if (self.index >= self.source.len) {
            return null;
        }
        const c = self.source[self.index];
        self.index += 1;
        return c;
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.peekChar()) |c| {
            if (!isWhitespace(c)) {
                break;
            }
            _ = self.nextChar();
        }
    }

    fn isWhitespace(c: u8) bool {
        return switch (c) {
            '\n', '\t', '\r', ' ' => true,
            else => false,
        };
    }

    fn isIdentifier(c: u8) bool {
        return switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '_' => true,
            else => false,
        };
    }

    fn isNumber(c: u8) bool {
        return switch (c) {
            '0'...'9' => true,
            else => false,
        };
    }
};
