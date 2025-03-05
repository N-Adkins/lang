const std = @import("std");
const ErrorContext = @import("ErrorContext.zig");
const Source = ErrorContext.Source;
const Lexer = @import("Lexer.zig");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();

    const allocator = debug_allocator.allocator();

    const source: Source = .{
        .filename = "test.lang",
        .text = "Test123_, ; ;; :: 9)(()() idk1823 128 3201)",
    };

    var err_ctx: ErrorContext = .{
        .allocator = allocator,
    };
    defer err_ctx.deinit();

    var lexer: Lexer = .{
        .allocator = allocator,
        .source = &source,
        .err_ctx = &err_ctx,
    };

    var token = try lexer.next();
    while (token.kind != .eof) {
        std.debug.print("Token {{ {}, \"{s}\" }}\n", .{ token.kind, source.text[token.start..token.end] });
        token = try lexer.next();
    }
}
