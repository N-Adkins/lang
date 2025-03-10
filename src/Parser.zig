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

fn parseType(self: *Self) !Ast.TypeId {
    const arena = self.ast.arena();

    // For now just identifiers
    const ident = try self.expect(.identifier);
    const str = ident.toSlice(self.source.text);
    const @"type" = Ast.Type.BuiltinTable.get(str) orelse {
        self.err_ctx.push(self.source, ident.start, "Failed to parse type, found identifier \"{s}\"", .{str});
        return error.InvalidType;
    };

    return self.ast.type_table.getOrInsert(arena, @"type");
}

fn parseTopLevel(self: *Self) !*Ast.Node {
    return self.parseFuncDecl();
}

fn parseFuncDecl(self: *Self) !*Ast.Node {
    const arena = self.ast.arena();

    try self.expect(.func_keyword);
    const ident = try self.expect(.identifier);
    const name = try arena.dupe(ident.toSlice(self.source.text));

    var args: std.ArrayListUnmanaged(Ast.Node.Kind.FunctionArg) = .empty;
    try self.expect(.left_paren);
    while (self.prev.kind != .comma) {
        const arg_ident = try self.expect(.identifier);
        try self.expect(.comma);

        const arg_type = try self.parseType();
        const arg_name = arena.dupe(u8, arg_ident.toSlice(self.source));
        try args.append(arena, .{
            .name = arg_name,
            .type = arg_type,
        });

        if (self.prev.kind == .right_paren) {
            break;
        }
        try self.expect(.comma);
    }
    try self.expect(.right_paren);

    const @"type" = try self.parseType();
    
    var body: std.ArrayListUnmanaged(*Ast.Node) = .empty;
    try self.expect(.left_curly);
    while (self.prev.kind != .semicolon) {
        const stmt = self.parseStatement();
        try body.append(arena, stmt);
        if (self.prev.kind == .right_curly) {
            break;
        }
        try self.expect(.semicolon);
    }
    
    const node = try arena.create(Ast.Node);
    node.* = .{
        .kind = .{ .func_decl = .{
            .name = name,
            .args = args.items,
            .body = body.items,
            .return_type = @"type",
        } },
        .source = self.source,
        .source_index = ident.start,
    };

    return node;
}

fn parseStatement(self: *Self) !*Ast.Node {
    return switch (self.prev.kind) {
        .var_keyword => self.parseVarDecl(),
        else => {
            try self.err_ctx.push(self.source, self.prev.start, "Expected statement, instead found token of type {}", .{self.prev.kind});
            return error.InvalidStatement;
        }
    };
}

fn parseVarDecl(self: *Self) !*Ast.Node {
    const arena = self.ast.arena();

    try self.expect(.var_keyword);
    const ident = try self.expect(.identifier);
    const name = try arena.dupe(ident.toSlice(self.source.text));

    try self.expect(.colon);
    const type = try self.parseType();

    try self.expect(.equals);
    const value = try self.parseExpr();
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
