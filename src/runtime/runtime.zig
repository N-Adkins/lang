const std = @import("std");
const value = @import("value.zig");
const vm = @import("vm.zig");

pub fn run(allocator: std.mem.Allocator, bytecode: []const u8) vm.RuntimeError!void {
    const constants = [0]value.Value{};
    var runtime = try vm.VM.init(allocator, bytecode, constants);
    defer runtime.deinit();
    try runtime.run();
}
