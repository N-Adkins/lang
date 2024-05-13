//! Wrapper over the language runtime, creates and runs a VM with the passed
//! bytecode and constants

const std = @import("std");
const value = @import("value.zig");
const vm = @import("vm.zig");

pub fn run(allocator: std.mem.Allocator, bytecode: [][]const u8, constants: []const value.Value) void {
    var rng_engine = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const rng = rng_engine.random();
    var runtime = vm.VM.init(allocator, rng, bytecode, constants);
    defer runtime.deinit();
    runtime.run();
}
