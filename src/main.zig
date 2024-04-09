const std = @import("std");
const lexer = @import("lexer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    const str = "test etst828 __8 328 3281 ( 0 138) {}";
    var lex = lexer.Lexer.init(&allocator, str);
    try lex.tokenize();
    while (lex.queue.popFirst()) |node| {
        std.debug.print("Raw: \"{s}\", {any}\n", .{str[node.data.start..node.data.end], node.data});
        allocator.destroy(node);
    }
}
