const std = @import("std");
const ErrorContext = @import("ErrorContext.zig");
const Source = ErrorContext.Source;
const Self = @This();

pub const Token = struct {
    pub const Kind = enum {
        eof,
        identifier,
        int_literal,
        left_curly,
        right_curly,
        left_paren,
        right_paren,
        comma,
        period,
        colon,
        semicolon,
        equals,
    };

    kind: Kind,
    start: usize,
    end: usize,

    pub fn toSlice(self: Token, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

err_ctx: *ErrorContext,
source: *const Source,
index: usize = 0,
allocator: std.mem.Allocator,

pub fn next(self: *Self) !Token {
    const State = enum {
        start,
        identifier,
        int_literal,
        invalid,
    };

    var result: Token = .{
        .kind = undefined,
        .start = self.index,
        .end = undefined,
    };

    state: switch (State.start) {
        .start => {
            switch (self.source.text[self.index]) {
                0 => {
                    if (self.index >= self.source.text.len) {
                        return .{
                            .kind = .eof,
                            .start = self.index,
                            .end = self.index,
                        };
                    }
                    continue :state .invalid;
                },
                '\n', ' ', '\t', '\r' => {
                    self.index += 1;
                    continue :state .start;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    result.kind = .identifier;
                    continue :state .identifier;
                },
                '0'...'9' => {
                    result.kind = .int_literal;
                    continue :state .int_literal;
                },
                '{' => {
                    self.index += 1;
                    result.kind = .left_curly;
                },
                '}' => {
                    self.index += 1;
                    result.kind = .right_curly;
                },
                '(' => {
                    self.index += 1;
                    result.kind = .left_paren;
                },
                ')' => {
                    self.index += 1;
                    result.kind = .right_paren;
                },
                ',' => {
                    self.index += 1;
                    result.kind = .comma;
                },
                '.' => {
                    self.index += 1;
                    result.kind = .period;
                },
                ':' => {
                    self.index += 1;
                    result.kind = .colon;
                },
                ';' => {
                    self.index += 1;
                    result.kind = .semicolon;
                },
                '=' => {
                    self.index += 1;
                    result.kind = .equals;
                },
                else => continue :state .invalid,
            }
        },
        .identifier => {
            self.index += 1;
            switch (self.source.text[self.index]) {
                'a'...'z', 'A'...'Z', '0'...'9', '_' => continue :state .identifier,
                else => {},
            }
        },
        .int_literal => {
            self.index += 1;
            switch (self.source.text[self.index]) {
                '0'...'9' => continue :state .int_literal,
                else => {},
            }
        },
        .invalid => {
            try self.err_ctx.push(self.source, result.start, "Found invalid lexeme during tokenization: '{c}'", .{self.source.text[self.index]});
            return error.InvalidLexeme;
        },
    }

    result.end = self.index;
    return result;
}
