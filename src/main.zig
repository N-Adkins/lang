const std = @import("std");
const lexer = @import("lexer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const str = "test +=e tst828- --__8 <=328 < 3281 v a a var( 0 138) {}";

    var lex = lexer.Lexer.init(&allocator, str);
    defer lex.deinit();

    try lex.tokenize();
    while (lex.queue.popFirst()) |node| {
        std.debug.print("Raw: \"{s}\", {any}\n", .{str[node.data.start..node.data.end], node.data});
        allocator.destroy(node);
    }
}
