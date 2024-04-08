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

    }

    fn pushToken(self: *Lexer, token: Token) LexerError!void {
        const node = try self.allocator.create(std.TailQueue(Token).Node);
        node.* = .{ .prev = null, .next = null, .data = token };
        self.queue.append(node);
    }
};
