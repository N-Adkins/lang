const std = @import("std");
const compiler = @import("compiler/compiler.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const str = @embedFile("examples/test.txt");
    
    compiler.compile(allocator, str) catch {};
}
