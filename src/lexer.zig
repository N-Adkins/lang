const std = @import("std");

pub const TokenTag = enum {
    identifier,
    number,
    l_paren,
    r_paren,
    l_curly,
    r_curly,
    comma,
    semicolon,
};

pub const Token = struct {
    tag: TokenTag,
    start: usize,
    end: usize,
    line: usize,
    col: usize,
};

pub const LexerError = error {
    UnexpectedCharacter,
} || std.mem.Allocator.Error;

pub const Lexer = struct {
    source: []const u8,
    index: usize = 0,
    line: usize = 1,
    col: usize = 1,
    queue: std.TailQueue(Token) = .{},
    allocator: *std.mem.Allocator,

    pub fn init(allocator: *std.mem.Allocator, source: []const u8) Lexer {
        return Lexer{
            .source = source,
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
        try self.pushToken(Token{ .tag = .number, .start = start, .end = end, .line = self.line, .col = self.col });
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
        try self.pushToken(Token{ .tag = .identifier, .start = start, .end = end, .line = self.line, .col = self.col });
    }

    fn tokenizeSpecial(self: *Lexer) LexerError!void {
        std.debug.assert(self.peekChar() != null);
        const start = self.index;
        const char = self.nextChar().?;
        const tag: TokenTag = switch (char) {
            '(' => .l_paren,
            ')' => .r_paren,
            '{' => .l_curly,
            '}' => .r_curly,
            ',' => .comma,
            ';' => .semicolon,
            else => return LexerError.UnexpectedCharacter,
        };
        const end = self.index;
        try self.pushToken(Token{ .tag = tag, .start = start, .end = end, .line = self.line, .col = self.col });
    }

    fn pushToken(self: *Lexer, token: Token) LexerError!void {
        const node = try self.allocator.create(std.TailQueue(Token).Node);
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
        self.col += 1;
        if (c == '\n') {
            self.line += 1;
            self.col = 1;
        }
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
