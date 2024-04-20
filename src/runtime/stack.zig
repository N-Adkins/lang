//! Generic Stack Structure

const std = @import("std");

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

        pub fn init(allocator: std.mem.Allocator, size: usize) Error!Self {
            const items = try allocator.alloc(T, size);
            return Self{
                .items = items,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.items);
        }

        pub fn getFrame(self: *Self) usize {
            return self.head;
        }

        pub fn popFrame(self: *Self, frame: usize) Error!void {
            while (self.head > frame) {
                _ = try self.pop();
            }
        }

        pub fn peekFrameOffset(self: *Self, frame: usize, offset: usize) Error!*T {
            if (frame +% offset > self.head) {
                return Error.Overflow;
            }
            return &self.items[frame + offset];
        }

        pub fn push(self: *Self, item: T) Error!void {
            if (self.head >= self.items.len) {
                return Error.Overflow;
            }
            self.items[self.head] = item;
            self.head += 1;
        }

        pub fn pop(self: *Self) Error!T {
            if (self.head < self.head -% 1) {
                return Error.Underflow;
            }
            self.head -= 1;
            return self.items[self.head];
        }

        pub fn peek(self: *Self) Error!*T {
            if (self.head < self.head -% 1) {
                return Error.Underflow;
            }
            return &self.items[self.head - 1];
        }
    };
}
