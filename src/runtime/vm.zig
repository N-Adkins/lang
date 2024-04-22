//! Monolithic runtime structure, executes bytecode with other data like
//! constants

const std = @import("std");
const byte = @import("bytecode.zig");
const gc = @import("gc.zig");
const stack = @import("stack.zig");
const value = @import("value.zig");

pub const Error = error{
    MalformedInstruction,
    InvalidConstant,
    InvalidCallFrame,
} || stack.Error;

/// Used in call stack to maintain function calls
const CallFrame = struct {
    stack_offset: usize, // call frame in eval stack
    index: usize, // bytecode index to return to
    func: usize, // function to return to
    root: bool = false,
};

/// Virtual machine, executes bytecode and maintains all runtime stacks
pub const VM = struct {
    current_func: usize = 0,
    bytes: [][]const u8,
    constants: []const value.Value,
    eval_stack: stack.Stack(value.Value),
    call_stack: stack.Stack(CallFrame),
    garbage_collector: gc.GC,
    pc: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, bytes: [][]const u8, constants: []const value.Value) Error!VM {
        var vm = VM{
            .bytes = bytes,
            .constants = constants,
            .eval_stack = try stack.Stack(value.Value).init(allocator, 0xFF),
            .call_stack = try stack.Stack(CallFrame).init(allocator, 0xFF),
            .garbage_collector = gc.GC.init(allocator),
            .allocator = allocator,
        };
        try vm.call_stack.push(CallFrame{ .index = 0, .func = 0, .stack_offset = 0, .root = true });
        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.eval_stack.deinit(self.allocator);
        self.call_stack.deinit(self.allocator);
    }

    /// Runs VM
    pub fn run(self: *VM) Error!void {
        while (self.pc < self.bytes[self.current_func].len) {
            try self.nextInstr();
        }
        while (self.eval_stack.head > 0) {
            _ = try self.eval_stack.pop();
            //std.debug.print("{any}\n", .{item});
        }
        self.garbage_collector.run(self.eval_stack.items[0..self.eval_stack.head]);
    }

    /// Executes the next instruction
    fn nextInstr(self: *VM) Error!void {
        const op: byte.Opcode = @enumFromInt(try self.nextByte());
        switch (op) {
            .CONSTANT => try self.opConstant(),
            .VAR_SET => try self.opVarSet(),
            .VAR_GET => try self.opVarGet(),
            .STACK_ALLOC => try self.opStackAlloc(),
            .ADD => try self.opAdd(),
            .SUB => try self.opSub(),
            .MUL => try self.opMul(),
            .DIV => try self.opDiv(),
            .CALL => try self.opCall(),
            .RETURN => try self.opReturn(),
            .CALL_BUILTIN => try self.opCallBuiltin(),
            .NEGATE => try self.opNegate(),
            .EQUAL => try self.opEqual(),
            .AND => try self.opAnd(),
            .OR => try self.opOr(),
            .BRANCH_NEQ => try self.opBranchNEQ(),
            .JUMP => try self.opJump(),
        }
    }

    fn opConstant(self: *VM) Error!void {
        const index = try self.nextByte();
        if (index >= self.constants.len) {
            return Error.InvalidConstant;
        }
        const constant = try self.constants[index].dupe(self.allocator);
        switch (constant.data) {
            .object => |obj| {
                self.garbage_collector.linkObject(obj);
            },
            else => {},
        }
        try self.eval_stack.push(constant);
    }

    fn opVarSet(self: *VM) Error!void {
        const offset = try self.nextByte();
        const frame = try self.call_stack.peek();
        const value_ptr = try self.eval_stack.peekFrameOffset(frame.stack_offset, offset);
        const new_value = try self.eval_stack.pop();
        value_ptr.* = new_value;
    }

    fn opVarGet(self: *VM) Error!void {
        const offset = try self.nextByte();
        const frame = try self.call_stack.peek();
        const value_ptr = try self.eval_stack.peekFrameOffset(frame.stack_offset, offset);
        try self.eval_stack.push(value_ptr.*);
    }

    fn opStackAlloc(self: *VM) Error!void {
        const amount = try self.nextByte();
        for (0..amount) |_| {
            try self.eval_stack.push(undefined);
        }
    }

    fn opAdd(self: *VM) Error!void {
        const rhs = try self.eval_stack.pop();
        const lhs = try self.eval_stack.pop();
        try self.eval_stack.push(.{
            .data = .{
                .number = lhs.data.number + rhs.data.number,
            },
        });
    }

    fn opSub(self: *VM) Error!void {
        const rhs = try self.eval_stack.pop();
        const lhs = try self.eval_stack.pop();
        try self.eval_stack.push(.{
            .data = .{
                .number = lhs.data.number - rhs.data.number,
            },
        });
    }

    fn opMul(self: *VM) Error!void {
        const rhs = try self.eval_stack.pop();
        const lhs = try self.eval_stack.pop();
        try self.eval_stack.push(.{
            .data = .{
                .number = lhs.data.number * rhs.data.number,
            },
        });
    }

    fn opDiv(self: *VM) Error!void {
        const rhs = try self.eval_stack.pop();
        const lhs = try self.eval_stack.pop();
        try self.eval_stack.push(.{
            .data = .{
                .number = lhs.data.number / rhs.data.number,
            },
        });
    }

    fn opCall(self: *VM) Error!void {
        const arg_count = try self.nextByte();
        const func = try self.eval_stack.pop();
        const frame = CallFrame{
            .func = self.current_func,
            .index = self.pc,
            .stack_offset = self.eval_stack.head - arg_count,
        };
        try self.call_stack.push(frame);
        self.current_func = func.data.func;
        self.pc = 0;
    }

    fn opReturn(self: *VM) Error!void {
        const is_return = (try self.nextByte()) != 0;
        const call_frame = try self.call_stack.pop();
        if (call_frame.root) {
            return;
        }
        self.current_func = call_frame.func;
        self.pc = call_frame.index;

        if (is_return) {
            const ret = try self.eval_stack.pop();
            try self.eval_stack.popFrame(call_frame.stack_offset);
            try self.eval_stack.push(ret);
        } else {
            try self.eval_stack.popFrame(call_frame.stack_offset);
        }
    }

    fn opCallBuiltin(self: *VM) Error!void {
        const idx = try self.nextByte();
        switch (idx) {
            0 => try self.builtinPrint(),
            1 => try self.builtinToString(),
            else => unreachable,
        }
    }

    fn opNegate(self: *VM) Error!void {
        const item = try self.eval_stack.pop();
        try self.eval_stack.push(value.Value{ .data = .{ .boolean = !item.data.boolean } });
    }

    fn opEqual(self: *VM) Error!void {
        const lhs = try self.eval_stack.pop();
        const rhs = try self.eval_stack.pop();
        try self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.equals(rhs) } });
    }

    fn opAnd(self: *VM) Error!void {
        const lhs = try self.eval_stack.pop();
        const rhs = try self.eval_stack.pop();
        try self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.data.boolean and rhs.data.boolean } });
    }

    fn opOr(self: *VM) Error!void {
        const lhs = try self.eval_stack.pop();
        const rhs = try self.eval_stack.pop();
        try self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.data.boolean or rhs.data.boolean } });
    }

    fn opBranchNEQ(self: *VM) Error!void {
        const offset = try self.nextByte();
        const item = try self.eval_stack.pop();
        if (!item.data.boolean) {
            self.pc += offset;
        }
    }

    fn opJump(self: *VM) Error!void {
        const offset = try self.nextByte();
        self.pc += offset;
    }

    fn builtinPrint(self: *VM) Error!void {
        const item = try self.eval_stack.pop();
        std.debug.print("{any}\n", .{item});
    }

    fn builtinToString(self: *VM) Error!void {
        const item = try self.eval_stack.pop();
        const raw = try std.fmt.allocPrint(self.allocator, "{any}", .{item});
        const object = try self.garbage_collector.newObject();
        object.data = .{
            .string = .{
                .raw = raw,
            },
        };
        try self.eval_stack.push(value.Value{ .data = .{ .object = object } });
    }

    /// Fetches the next byte and errors if there isn't one
    fn nextByte(self: *VM) Error!u8 {
        if (self.pc >= self.bytes[self.current_func].len) {
            return Error.MalformedInstruction;
        }
        const ret = self.bytes[self.current_func][self.pc];
        self.pc += 1;
        return ret;
    }
};
