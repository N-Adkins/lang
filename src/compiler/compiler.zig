const std = @import("std");
const err = @import("error.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbol_pass = @import("passes/symbol_populate.zig");
const type_pass = @import("passes/type_check.zig");
const pretty = @import("pretty");

pub fn compile(allocator: std.mem.Allocator, source: []const u8) anyerror!void {
    var err_ctx = err.ErrorContext{
        .source = source,
        .allocator = allocator,
    };
    defer err_ctx.deinit();

    runPasses(allocator, &err_ctx, source) catch |comp_err| {
        if (err_ctx.hasErrors()) {
            err_ctx.printErrors();
        }
        return comp_err;
    };
}

fn runPasses(allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, source: []const u8) anyerror!void {
    var lex = lexer.Lexer.init(allocator, err_ctx, source);
    defer lex.deinit();
    try lex.tokenize();

    var parse = parser.Parser.init(allocator, err_ctx, &lex);
    defer parse.deinit();
    try parse.parse();

    var symbol_populate_pass = symbol_pass.SymbolPass.init(allocator, err_ctx, &parse.root);
    defer symbol_populate_pass.deinit();
    try symbol_populate_pass.run();

    var type_check_pass = type_pass.TypePass.init(err_ctx, &parse.root);
    try type_check_pass.run();

    try pretty.print(allocator, parse.root, .{});
}
