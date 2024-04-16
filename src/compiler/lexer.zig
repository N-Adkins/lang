const std = @import("std");
const err = @import("error.zig");

pub const TokenTag = enum {
    identifier,
    number,
    l_paren,
    r_paren,
    l_curly,
    r_curly,
    comma,
    period,
    colon,
    semicolon,
    minus,
    minus_minus,
    minus_equals,
    plus,
    plus_plus,
    plus_equals,
    equals,
    equals_equals,
    less_than,
    less_than_equals,
    greater_than,
    greater_than_equals,
    keyword_var,
    keyword_if,
};

const keyword_lookup = std.ComptimeStringMap(TokenTag, .{
    .{ "var", TokenTag.keyword_var },
    .{ "if", TokenTag.keyword_if },
});

pub const Token = struct {
    tag: TokenTag,
    start: usize,
    end: usize,
};

pub const LexerError = error{
    UnexpectedCharacter,
} || std.mem.Allocator.Error;

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

    pub fn deinit(self: *Lexer) void {
        while (self.queue.popFirst()) |node| {
            self.allocator.destroy(node);
        }
    }

    pub fn peekToken(self: *Lexer) ?*Token {
        if (self.queue.first) |node| {
            return &node.data;
        }
        return null;
    }

    pub fn nextToken(self: *Lexer) ?Token {
        if (self.queue.popFirst()) |node| {
            const token = node.data;
            self.allocator.destroy(node);
            return token;
        }
        return null;
    }

    pub fn tokenize(self: *Lexer) LexerError!void {
        while (self.index < self.source.len) {
            self.skipWhitespace();
            if (self.peekChar() == null) {
                break;
            }
            try self.tokenizeNext();
        }
    }

    fn tokenizeNext(self: *Lexer) LexerError!void {
        std.debug.assert(self.peekChar() != null);
        const next = self.peekChar().?;
        if (isNumber(next)) {
            try self.tokenizeNumber();
        } else if (isIdentifier(next)) {
            try self.tokenizeIdentifier();
        } else {
            try self.tokenizeSpecial();
        }
    }

    fn tokenizeNumber(self: *Lexer) LexerError!void {
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

    fn tokenizeIdentifier(self: *Lexer) LexerError!void {
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

    fn tokenizeSpecial(self: *Lexer) LexerError!void {
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
                    '=' => {
                        _ = self.nextChar();
                        tag = .minus_equals;
                    },
                    else => tag = .minus,
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
            ':' => tag = .colon,
            ';' => tag = .semicolon,
            else => {
                try self.err_ctx.newError(.unexpected_character, "Unexpected character: '{c}'", .{char}, start);
                return LexerError.UnexpectedCharacter;
            },
        }
        const end = self.index;
        try self.pushToken(Token{ .tag = tag, .start = start, .end = end });
    }

    fn pushToken(self: *Lexer, token: Token) LexerError!void {
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