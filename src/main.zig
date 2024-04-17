const std = @import("std");
const byte = @import("runtime/bytecode.zig");
const compiler = @import("compiler/compiler.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const str = @embedFile("examples/test.txt");

    const bytecode = compiler.compile(allocator, str) catch {
        return;
    };
    defer allocator.free(bytecode);

    byte.dumpBytecode(bytecode);
}
