const std = @import("std");

pub const Frame = struct {
    offset: usize,
};

pub const StackError = error{
    Overflow,
    Underflow,
} || std.mem.Allocator.Error;

pub const Stack = struct {
    const DEFAULT_SIZE: usize = 256;
    items: []Frame,
    head: usize = 0,

    pub fn init(allocator: std.mem.Allocator) StackError!Stack {
        const items = try allocator.alloc(Frame, DEFAULT_SIZE);
        return Stack{
            .items = items,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Stack) void {
        self.allocator.free(self.items);
    }

    pub fn push(self: *Stack, item: Frame) StackError!void {
        if (self.head >= self.items.len) {
            return StackError.Overflow;
        }
        self.items[self.head] = item;
        self.head += 1;
    }

    pub fn pop(self: *Stack) StackError!Frame {
        if (self.head > self.head -% 1) {
            return StackError.Underflow;
        }
        self.head -= 1;
        return self.items[self.head];
    }

    pub fn peek(self: *Stack) StackError!*Frame {
        if (self.head > self.head -% 1) {
            return StackError.Underflow;
        }
        return &self.items[self.head - 1];
    }

    pub fn dump(self: *Stack) void {}
};
