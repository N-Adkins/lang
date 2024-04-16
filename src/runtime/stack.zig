const std = @import("std");
const value = @import("value.zig");

pub const StackError = error{
    Overflow,
    Underflow,
} || std.mem.Allocator.Error;

pub const Stack = struct {
    const DEFAULT_SIZE: usize = 64;
    const Frame = struct {
        index: usize,
    };

    items: []value.Value,
    head: usize = 0,
    dynamic: bool,
    allocator: std.mem.Allocator,

    pub fn initStatic(allocator: std.mem.Allocator, size: usize) StackError!Stack {
        const items = try allocator.alloc(value.Value, size);
        return Stack{
            .items = items,
            .dynamic = false,
            .allocator = allocator,
        };
    }

    pub fn initDynamic(allocator: std.mem.Allocator) StackError!Stack {
        const items = try allocator.alloc(value.Value, DEFAULT_SIZE);
        return Stack{
            .items = items,
            .dynamic = true,
            .allocator = allocator,
        };
    }

    pub fn getFrame(self: *Stack) Frame {
        return Frame{
            .index = self.head,
        };
    }

    pub fn peekFrameOffset(self: *Stack, frame: Frame, offset: usize) StackError!value.Value {
        const index = frame.index + offset;
        if (index >= self.items.len) {
            return StackError.Overflow;
        }
        return &self.items[index];
    }

    pub fn push(self: *Stack, item: value.Value) StackError!void {
        if (self.head >= self.items.len) {
            if (self.dynamic) {
                self.items = try self.allocator.realloc(self.items, self.items.len * 2);
            } else {
                return StackError.Overflow;
            }
        }
        self.items[self.head] = item;
        self.head += 1;
    }

    pub fn pop(self: *Stack) StackError!value.Value {
        if (self.head > self.head -% 1) {
            return StackError.Underflow;
        }
        self.head -= 1;
        return self.items[self.head];
    }

    pub fn peek(self: *Stack) StackError!*value.Value {
        if (self.head > self.head -% 1) {
            return StackError.Underflow;
        }
        return &self.items[self.head - 1];
    }
};
