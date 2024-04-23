//! Generic Stack Structure

const std = @import("std");
const vm = @import("vm.zig");

pub const Error = error{
    Overflow,
    Underflow,
} || std.mem.Allocator.Error;

/// Stack structure used for the runtime, like the evaluation stack and the
/// call stack. Static stack size.
pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        head: usize = 0,

        pub fn init(allocator: std.mem.Allocator, size: usize) Self {
            const items = allocator.alloc(T, size) catch |err| {
                @setCold(true);
                vm.errorHandle(err);
                unreachable;
            };
            return Self{
                .items = items,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.items);
        }

        pub inline fn getFrame(self: *Self) usize {
            return self.head;
        }

        pub inline fn popFrame(self: *Self, frame: usize) void {
            while (self.head > frame) {
                _ = self.pop();
            }
        }

        pub inline fn peekFrameOffset(self: *Self, frame: usize, offset: usize) *T {
            if (frame +% offset > self.head) {
                @setCold(true);
                vm.errorHandle(Error.Overflow);
                unreachable;
            }
            return &self.items[frame + offset];
        }

        pub inline fn push(self: *Self, item: T) void {
            if (self.head >= self.items.len) {
                @setCold(true);
                vm.errorHandle(Error.Overflow);
                unreachable;
            }
            self.items[self.head] = item;
            self.head += 1;
        }

        pub inline fn pop(self: *Self) T {
            if (self.head < self.head -% 1) {
                @setCold(true);
                vm.errorHandle(Error.Underflow);
                unreachable;
            }
            self.head -= 1;
            return self.items[self.head];
        }

        pub inline fn peek(self: *Self) *T {
            if (self.head < self.head -% 1) {
                @setCold(true);
                vm.errorHandle(Error.Underflow);
                unreachable;
            }
            return &self.items[self.head - 1];
        }
    };
}
