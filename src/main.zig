const std = @import("std");
const byte = @import("runtime/bytecode.zig");
const compiler = @import("compiler/compiler.zig");
const runtime = @import("runtime/runtime.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const str = @embedFile("examples/test.txt");

    var compile_result = compiler.compile(allocator, str) catch {
        return;
    };
    defer compile_result.deinit(allocator);
    byte.dumpBytecode(compile_result.bytecode);

    try runtime.run(allocator, compile_result.bytecode, compile_result.constants);
}
