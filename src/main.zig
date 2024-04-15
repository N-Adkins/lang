const std = @import("std");
const err = @import("error.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbol = @import("symbol.zig");
const pretty = @import("pretty");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const str = "var test: number  0;\nvar test_other: number = 4;";
    
    var err_ctx  = err.ErrorContext{
        .source = str,
        .allocator = allocator,
    };

    var lex = lexer.Lexer.init(allocator, &err_ctx, str);
    defer lex.deinit();
    lex.tokenize() catch {
        if (err_ctx.hasErrors()) {
            err_ctx.printErrors();
            return 1;
        } 
    };

    //while (lex.queue.popFirst()) |node| {
    //      std.debug.print("Raw: \"{s}\", {any}\n", .{ str[node.data.start..node.data.end], node.data });
    //      allocator.destroy(node);
    //}

    var parse = parser.Parser.init(allocator, &err_ctx, &lex);
    defer parse.deinit();
    parse.parse() catch {
        if (err_ctx.hasErrors()) {
            err_ctx.printErrors();
            return 1;
        }
    };

    //try symbol.checkSymbols(&parse.root);

    try pretty.print(allocator, parse.root, .{});

    return 0;
}
