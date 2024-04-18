const std = @import("std");

pub const StackError = error{
    Overflow,
    Underflow,
} || std.mem.Allocator.Error;

pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        head: usize = 0,

        pub fn init(allocator: std.mem.Allocator, size: usize) StackError!Self {
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

        pub fn popFrame(self: *Self, frame: usize) StackError!void {
            while (self.items.len > frame) {
                _ = try self.pop();
            }
        }

        pub fn peekFrameOffset(self: *Self, frame: usize, offset: usize) StackError!*T {
            if (frame +% offset > self.head) {
                return StackError.Overflow;
            }
            return &self.items[frame + offset];
        }

        pub fn push(self: *Self, item: T) StackError!void {
            if (self.head >= self.items.len) {
                return StackError.Overflow;
            }
            self.items[self.head] = item;
            self.head += 1;
        }

        pub fn pop(self: *Self) StackError!T {
            if (self.head < self.head -% 1) {
                return StackError.Underflow;
            }
            self.head -= 1;
            return self.items[self.head];
        }

        pub fn peek(self: *Self) StackError!*T {
            if (self.head < self.head -% 1) {
                return StackError.Underflow;
            }
            return &self.items[self.head - 1];
        }
    };
}
