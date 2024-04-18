//! Wrapper over the language runtime, creates and runs a VM with the passed
//! bytecode and constants

const std = @import("std");
const value = @import("value.zig");
const vm = @import("vm.zig");

pub fn run(allocator: std.mem.Allocator, bytecode: []const u8, constants: []const value.Value) vm.Error!void {
    var runtime = try vm.VM.init(allocator, bytecode, constants);
    defer runtime.deinit();
    try runtime.run();
}
