const std = @import("std");
const Ast = @import("Ast.zig");
const ErrorContext = @import("ErrorContext.zig");
const Lexer = @import("Lexer.zig");
const Source = ErrorContext.Source;
const Self = @This();

err_ctx: *ErrorContext,
source: *const Source,
lexer: *Lexer,
ast: Ast,
prev: Lexer.Token = undefined,
current: Lexer.Token = undefined,

pub fn init(allocator: std.mem.Allocator, err_ctx: *ErrorContext, source: *const Source, lexer: *Lexer) Self {
    return .{
        .err_ctx = err_ctx,
        .source = source,
        .lexer = lexer,
        .ast = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.ast.deinit();
}

pub fn parse(self: *Self) !void {
    const arena = self.ast.arena();

    self.prev = try self.lexer.next();
    self.current = try self.lexer.next();

    var body: std.ArrayListUnmanaged(*Ast.Node) = .empty;
    while (self.prev.kind != .eof) {
        const top_level = try self.parseTopLevel();
        body.append(arena, top_level);
    }

    self.ast.body = body;
}

fn parseTopLevel(self: *Self) !*Ast.Node {
    return self.parseFuncDecl();
}

fn parseFuncDecl(self: *Self) !*Ast.Node {
    try self.expect(.func_keyword);
    const ident = self.expect(.identifier);
    try self.expect(.left_paren);
    try self.expect(.right_paren);
}

fn nextToken(self: *Self) void {
    self.prev = self.current;
    self.current = self.lexer.next();
}

fn expect(self: *Self, kind: Lexer.Token.Kind) !Lexer.Token {
    if (self.prev.kind == kind) {
        const token = self.prev;
        self.nextToken();
        return token;
    }

    try self.err_ctx.push(self.source, self.prev.start, "Expected token kind \"{}\", instead found \"{}\"", .{ kind, self.prev.kind });
    return error.UnexpectedToken;
}
