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

    if (std.os.argv.len < 2) {
        std.debug.print("Expected filepath\n", .{});
        return;
    }

    const filepath: []const u8 = std.mem.span(std.os.argv[1]);

    const file = std.fs.cwd().openFile(filepath, .{}) catch |err| {
        std.debug.print("Failed to load file \"{s}\": {}\n", .{ filepath, err });
        return;
    };
    defer file.close();

    const reader = file.reader();
    const str = try reader.readAllAlloc(allocator, 0xFFFF);
    defer allocator.free(str);

    var compile_result = compiler.compile(allocator, str) catch {
        return;
    };
    defer compile_result.deinit(allocator);
    byte.dumpBytecode(compile_result.bytecode);

    runtime.run(allocator, compile_result.bytecode, compile_result.constants);
}
