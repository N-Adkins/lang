const std = @import("std");
const byte = @import("bytecode.zig");
const stack = @import("stack.zig");
const value = @import("value.zig");

pub const RuntimeError = error{
    MalformedInstruction,
    InvalidConstant,
    InvalidCallFrame,
} || stack.StackError;

const CallFrame = struct {
    index: usize,
};

pub const VM = struct {
    bytes: []const u8,
    constants: []const value.Value,
    eval_stack: stack.Stack(value.Value),
    call_stack: stack.Stack(CallFrame),
    pc: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, bytes: []const u8, constants: []const value.Value) RuntimeError!VM {
        return VM{
            .bytes = bytes,
            .constants = constants,
            .eval_stack = stack.Stack(value.Value).init(allocator, 0xFF),
            .call_stack = stack.Stack(usize).init(allocator, 0xFF),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *VM) void {
        self.eval_stack.deinit(self.allocator);
        self.call_stack.deinit(self.allocator);
    }

    pub fn run(self: *VM) RuntimeError!void {
        while (self.pc < self.bytes.len) {
            self.nextInstr();
        }
    }

    fn nextInstr(self: *VM) RuntimeError!void {
        const op: byte.Opcode = @enumFromInt(try self.nextByte());
        switch (op) {
            .CONSTANT => try self.opConstant(),
            .VAR_SET => try self.opVarSet(),
            .VAR_GET => try self.opVarGet(),
        }
    }

    fn opConstant(self: *VM) RuntimeError!void {
        const index = try self.nextByte();
        if (index >= self.constants.len) {
            return RuntimeError.InvalidConstant;
        }
        const constant = self.constants[index];
        try self.value_stack.push(constant);
    }

    fn opVarSet(self: *VM) RuntimeError!void {
        const offset = try self.nextByte();

        if (self.call_stack.peek() == null) {
            return RuntimeError.InvalidCallFrame;
        }

        const value_ptr = try self.value_stack.peekFrameOffset(self.call_stack.peek().?.offset, offset);
        const new_value = try self.value_stack.pop();
        value_ptr.* = new_value;
    }

    fn opVarGet(self: *VM) RuntimeError!void {
        const offset = try self.nextByte();

        if (self.call_stack.peek() == null) {
            return RuntimeError.InvalidCallFrame;
        }

        const value_ptr = try self.value_stack.peekFrameOffset(self.call_stack.peek().?.offset, offset);
        try self.value_stack.push(value_ptr.*);
    }

    fn nextByte(self: *VM) RuntimeError!u8 {
        if (self.pc >= self.bytes.len) {
            return RuntimeError.MalformedInstruction;
        }
        const ret = self.bytes[self.pc];
        self.pc += 1;
        return ret;
    }
};
