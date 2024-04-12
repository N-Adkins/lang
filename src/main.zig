const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbol = @import("symbol.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    const str = "var test = 0; var test_other = 2;";

    var lex = lexer.Lexer.init(&allocator, str);
    defer lex.deinit();

    try lex.tokenize();
    //while (lex.queue.popFirst()) |node| {
    //      std.debug.print("Raw: \"{s}\", {any}\n", .{ str[node.data.start..node.data.end], node.data });
    //      allocator.destroy(node);
    //}

    var parse = parser.Parser.init(&lex, &allocator);
    defer parse.deinit();

    try parse.parse();

    try symbol.checkSymbols(&parse.root);
}
