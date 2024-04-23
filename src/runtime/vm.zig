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
    ArrayOutOfBounds,
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
            .eval_stack = try stack.Stack(value.Value).init(allocator, 0xFFFF),
            .call_stack = try stack.Stack(CallFrame).init(allocator, 0xFFFF),
            .garbage_collector = gc.GC.init(allocator),
            .allocator = allocator,
        };
        try vm.call_stack.push(CallFrame{ .index = 0, .func = 0, .stack_offset = 0, .root = true });
        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.eval_stack.deinit(self.allocator);
        self.call_stack.deinit(self.allocator);
        self.garbage_collector.deinit();
    }

    /// Runs VM
    pub inline fn run(self: *VM) Error!void {
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
    inline fn nextInstr(self: *VM) Error!void {
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
            .MOD => try self.opMod(),
            .CALL => try self.opCall(),
            .RETURN => try self.opReturn(),
            .CALL_BUILTIN => try self.opCallBuiltin(),
            .NEGATE => try self.opNegate(),
            .EQUAL => try self.opEqual(),
            .GREATER_THAN => try self.opGreaterThan(),
            .GREATER_THAN_EQUALS => try self.opGreaterThanEquals(),
            .AND => try self.opAnd(),
            .OR => try self.opOr(),
            .BRANCH_NEQ => try self.opBranchNEQ(),
            .JUMP => try self.opJump(),
            .ARRAY_INIT => try self.opArrayInit(),
            .ARRAY_PUSH => try self.opArrayPush(),
            .ARRAY_GET => try self.opArrayGet(),
            .ARRAY_SET => try self.opArraySet(),
        }
    }

    inline fn opConstant(self: *VM) Error!void {
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

    inline fn opVarSet(self: *VM) Error!void {
        const offset = try self.nextByte();
        const frame = try self.call_stack.peek();
        const value_ptr = try self.eval_stack.peekFrameOffset(frame.stack_offset, offset);
        const new_value = try self.eval_stack.pop();
        value_ptr.* = new_value;
    }

    inline fn opVarGet(self: *VM) Error!void {
        const offset = try self.nextByte();
        const frame = try self.call_stack.peek();
        const value_ptr = try self.eval_stack.peekFrameOffset(frame.stack_offset, offset);
        try self.eval_stack.push(value_ptr.*);
    }

    inline fn opStackAlloc(self: *VM) Error!void {
        const amount = try self.nextByte();
        for (0..amount) |_| {
            try self.eval_stack.push(undefined);
        }
    }

    inline fn opAdd(self: *VM) Error!void {
        const rhs = try self.eval_stack.pop();
        const lhs = try self.eval_stack.pop();
        try self.eval_stack.push(.{
            .data = .{
                .number = lhs.data.number + rhs.data.number,
            },
        });
    }

    inline fn opSub(self: *VM) Error!void {
        const rhs = try self.eval_stack.pop();
        const lhs = try self.eval_stack.pop();
        try self.eval_stack.push(.{
            .data = .{
                .number = lhs.data.number - rhs.data.number,
            },
        });
    }

    inline fn opMul(self: *VM) Error!void {
        const rhs = try self.eval_stack.pop();
        const lhs = try self.eval_stack.pop();
        try self.eval_stack.push(.{
            .data = .{
                .number = lhs.data.number * rhs.data.number,
            },
        });
    }

    inline fn opDiv(self: *VM) Error!void {
        const rhs = try self.eval_stack.pop();
        const lhs = try self.eval_stack.pop();
        try self.eval_stack.push(.{
            .data = .{
                .number = lhs.data.number / rhs.data.number,
            },
        });
    }

    inline fn opMod(self: *VM) Error!void {
        const rhs = try self.eval_stack.pop();
        const lhs = try self.eval_stack.pop();
        try self.eval_stack.push(.{
            .data = .{
                .number = @mod(lhs.data.number, rhs.data.number),
            },
        });
    }

    inline fn opCall(self: *VM) Error!void {
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

    inline fn opReturn(self: *VM) Error!void {
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

    inline fn opCallBuiltin(self: *VM) Error!void {
        const idx = try self.nextByte();
        switch (idx) {
            0 => try self.builtinPrint(),
            1 => try self.builtinToString(),
            2 => try self.builtinLength(),
            else => unreachable,
        }
    }

    inline fn opNegate(self: *VM) Error!void {
        const item = try self.eval_stack.pop();
        try self.eval_stack.push(value.Value{ .data = .{ .boolean = !item.data.boolean } });
    }

    inline fn opEqual(self: *VM) Error!void {
        const lhs = try self.eval_stack.pop();
        const rhs = try self.eval_stack.pop();
        try self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.equals(rhs) } });
    }

    inline fn opGreaterThan(self: *VM) Error!void {
        const lhs = try self.eval_stack.pop();
        const rhs = try self.eval_stack.pop();
        try self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.data.number > rhs.data.number } });
    }

    inline fn opGreaterThanEquals(self: *VM) Error!void {
        const lhs = try self.eval_stack.pop();
        const rhs = try self.eval_stack.pop();
        try self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.data.number >= rhs.data.number } });
    }

    inline fn opAnd(self: *VM) Error!void {
        const lhs = try self.eval_stack.pop();
        const rhs = try self.eval_stack.pop();
        try self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.data.boolean and rhs.data.boolean } });
    }

    inline fn opOr(self: *VM) Error!void {
        const lhs = try self.eval_stack.pop();
        const rhs = try self.eval_stack.pop();
        try self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.data.boolean or rhs.data.boolean } });
    }

    inline fn opBranchNEQ(self: *VM) Error!void {
        const offset = try self.nextByte();
        const item = try self.eval_stack.pop();
        if (!item.data.boolean) {
            self.pc += offset;
        }
    }

    inline fn opJump(self: *VM) Error!void {
        const offset = try self.nextByte();
        self.pc += offset;
    }

    inline fn opArrayInit(self: *VM) Error!void {
        const items = try self.nextByte();
        var array = try std.ArrayListUnmanaged(value.Value).initCapacity(self.allocator, @intCast(items));
        for (0..items) |_| {
            try array.append(self.allocator, try self.eval_stack.pop());
        }
        const obj = try self.garbage_collector.newObject();
        obj.* = .{
            .data = .{
                .array = .{
                    .items = array,
                },
            },
        };
        try self.eval_stack.push(value.Value{ .data = .{ .object = obj } });
    }

    inline fn opArrayPush(self: *VM) Error!void {
        const array_obj = try self.eval_stack.pop();
        var array = &array_obj.data.object.data.array.items;
        const item = try self.eval_stack.pop();
        try array.append(self.allocator, item);
    }

    inline fn opArrayGet(self: *VM) Error!void {
        const array_obj = try self.eval_stack.pop();
        const array = &array_obj.data.object.data.array.items;
        const index_value = try self.eval_stack.pop();
        const index: usize = @intFromFloat(@trunc(index_value.data.number));
        if (array.items.len <= index) {
            return Error.ArrayOutOfBounds;
        }
        try self.eval_stack.push(array.items[index]);
    }

    inline fn opArraySet(self: *VM) Error!void {
        const array_obj = try self.eval_stack.pop();
        var array = &array_obj.data.object.data.array.items;
        const index_value = try self.eval_stack.pop();
        const index: usize = @intFromFloat(@trunc(index_value.data.number));
        const item = try self.eval_stack.pop();
        if (array.items.len <= index) {
            return Error.ArrayOutOfBounds;
        }
        array.items[index] = item;
    }

    inline fn builtinPrint(self: *VM) Error!void {
        const item = try self.eval_stack.pop();
        std.debug.print("{any}\n", .{item});
    }

    inline fn builtinToString(self: *VM) Error!void {
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

    inline fn builtinLength(self: *VM) Error!void {
        const array = try self.eval_stack.pop();
        try self.eval_stack.push(value.Value{ .data = .{ .number = @floatFromInt(array.data.object.data.array.items.items.len) } });
    }

    /// Fetches the next byte and errors if there isn't one
    inline fn nextByte(self: *VM) Error!u8 {
        if (self.pc >= self.bytes[self.current_func].len) {
            return Error.MalformedInstruction;
        }
        const ret = self.bytes[self.current_func][self.pc];
        self.pc += 1;
        return ret;
    }
};
