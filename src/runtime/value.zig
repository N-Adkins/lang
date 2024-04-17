const std = @import("std");

// data must be 8 bytes or lower
pub const Value = struct {
    data: union(enum) {
        number: i64,
    },
};

pub const StackError = error{
    Overflow,
    Underflow,
} || std.mem.Allocator.Error;

pub const Stack = struct {
    const DEFAULT_SIZE: usize = 64;
    pub const ValueFrame = struct {
        index: usize,
    };

    items: []Value,
    head: usize = 0,
    dynamic: bool,
    allocator: std.mem.Allocator,

    pub fn initStatic(allocator: std.mem.Allocator, size: usize) StackError!Stack {
        const items = try allocator.alloc(Value, size);
        return Stack{
            .items = items,
            .dynamic = false,
            .allocator = allocator,
        };
    }

    pub fn initDynamic(allocator: std.mem.Allocator) StackError!Stack {
        const items = try allocator.alloc(Value, DEFAULT_SIZE);
        return Stack{
            .items = items,
            .dynamic = true,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Stack) void {
        self.allocator.free(self.items);
    }

    pub fn getFrame(self: *Stack) usize {
        return self.head;
    }

    pub fn peekFrameOffset(self: *Stack, frame: usize, offset: usize) StackError!*Value {
        const index = frame + offset;
        if (index >= self.items.len) {
            return StackError.Overflow;
        }
        return &self.items[index];
    }

    pub fn push(self: *Stack, item: Value) StackError!void {
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

    pub fn pop(self: *Stack) StackError!Value {
        if (self.head > self.head -% 1) {
            return StackError.Underflow;
        }
        self.head -= 1;
        return self.items[self.head];
    }

    pub fn peek(self: *Stack) StackError!*Value {
        if (self.head > self.head -% 1) {
            return StackError.Underflow;
        }
        return &self.items[self.head - 1];
    }
};
