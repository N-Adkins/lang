const std = @import("std");
const Self = @This();

pub const Source = struct {
    filename: []const u8,
    text: [:0]const u8,

    pub fn deinit(self: *Source, allocator: std.mem.Allocator) void {
        allocator.free(self.filename);
        allocator.free(self.text);
    }
};

pub const CompileError = struct {
    message: []const u8,
    source: *const Source,
    index: usize,

    pub fn deinit(self: *CompileError, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};

errors: std.ArrayListUnmanaged(CompileError) = .{},
allocator: std.mem.Allocator,

pub fn push(self: *Self, source: *const Source, index: usize, comptime fmt: []const u8, args: anytype) !void {
    const message = try std.fmt.allocPrint(self.allocator, fmt, args);
    try self.errors.append(self.allocator, .{
        .message = message,
        .source = source,
        .index = index,
    });
}

pub fn deinit(self: *Self) void {
    for (self.errors.items) |*err| {
        err.deinit(self.allocator);
    }
}
