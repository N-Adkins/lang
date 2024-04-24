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

pub fn errorHandle(err: Error) void {
    @setCold(true);
    std.debug.print("Runtime Error: \"{s}\"\n", .{@errorName(err)});
    std.posix.exit(0);
}

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
    err: ?Error = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, bytes: [][]const u8, constants: []const value.Value) VM {
        var vm = VM{
            .bytes = bytes,
            .constants = constants,
            .eval_stack = stack.Stack(value.Value).init(allocator, 0xFFFF),
            .call_stack = stack.Stack(CallFrame).init(allocator, 0xFFFF),
            .garbage_collector = gc.GC.init(allocator),
            .allocator = allocator,
        };
        vm.call_stack.push(CallFrame{ .index = 0, .func = 0, .stack_offset = 0, .root = true });
        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.eval_stack.deinit(self.allocator);
        self.call_stack.deinit(self.allocator);
        self.garbage_collector.deinit();
    }

    /// Runs VM
    pub inline fn run(self: *VM) void {
        while (self.pc < self.bytes[self.current_func].len) {
            self.nextInstr();
        }
        while (self.eval_stack.head > 0) {
            _ = self.eval_stack.pop();
            //std.debug.print("{any}\n", .{item});
        }
        self.garbage_collector.run(self.eval_stack.items[0..self.eval_stack.head]);
    }

    /// Executes the next instruction
    inline fn nextInstr(self: *VM) void {
        const op: byte.Opcode = @enumFromInt(self.nextByte());
        switch (op) {
            .CONSTANT => self.opConstant(),
            .VAR_SET => self.opVarSet(),
            .VAR_GET => self.opVarGet(),
            .STACK_ALLOC => self.opStackAlloc(),
            .ADD => self.opAdd(),
            .SUB => self.opSub(),
            .MUL => self.opMul(),
            .DIV => self.opDiv(),
            .MOD => self.opMod(),
            .CALL => self.opCall(),
            .RETURN => self.opReturn(),
            .CALL_BUILTIN => self.opCallBuiltin(),
            .NEGATE => self.opNegate(),
            .EQUAL => self.opEqual(),
            .GREATER_THAN => self.opGreaterThan(),
            .GREATER_THAN_EQUALS => self.opGreaterThanEquals(),
            .LESS_THAN => self.opLessThan(),
            .LESS_THAN_EQUALS => self.opLessThanEquals(),
            .AND => self.opAnd(),
            .OR => self.opOr(),
            .BRANCH_NEQ => self.opBranchNEQ(),
            .JUMP => self.opJump(),
            .JUMP_BACK => self.opJumpBack(),
            .ARRAY_INIT => self.opArrayInit(),
            .ARRAY_PUSH => self.opArrayPush(),
            .ARRAY_GET => self.opArrayGet(),
            .ARRAY_SET => self.opArraySet(),
        }
    }

    inline fn opConstant(self: *VM) void {
        const index = self.nextByte();
        const constant = self.constants[index].dupe(self.allocator);
        switch (constant.data) {
            .object => |obj| {
                self.garbage_collector.linkObject(obj);
            },
            else => {},
        }
        self.eval_stack.push(constant);
    }

    inline fn opVarSet(self: *VM) void {
        const offset = self.nextByte();
        const frame = self.call_stack.peek();
        const value_ptr = self.eval_stack.peekFrameOffset(frame.stack_offset, offset);
        const new_value = self.eval_stack.pop();
        value_ptr.* = new_value;
    }

    inline fn opVarGet(self: *VM) void {
        const offset = self.nextByte();
        const frame = self.call_stack.peek();
        const value_ptr = self.eval_stack.peekFrameOffset(frame.stack_offset, offset);
        self.eval_stack.push(value_ptr.*);
    }

    inline fn opStackAlloc(self: *VM) void {
        const amount = self.nextByte();
        for (0..amount) |_| {
            self.eval_stack.push(undefined);
        }
    }

    inline fn opAdd(self: *VM) void {
        const lhs = self.eval_stack.pop();
        const rhs = self.eval_stack.pop();
        self.eval_stack.push(.{
            .data = .{
                .integer = lhs.data.integer + rhs.data.integer,
            },
        });
    }

    inline fn opSub(self: *VM) void {
        const lhs = self.eval_stack.pop();
        const rhs = self.eval_stack.pop();
        self.eval_stack.push(.{
            .data = .{
                .integer = lhs.data.integer - rhs.data.integer,
            },
        });
    }

    inline fn opMul(self: *VM) void {
        const lhs = self.eval_stack.pop();
        const rhs = self.eval_stack.pop();
        self.eval_stack.push(.{
            .data = .{
                .integer = lhs.data.integer * rhs.data.integer,
            },
        });
    }

    inline fn opDiv(self: *VM) void {
        const lhs = self.eval_stack.pop();
        const rhs = self.eval_stack.pop();
        self.eval_stack.push(.{
            .data = .{
                .integer = @divTrunc(lhs.data.integer, rhs.data.integer),
            },
        });
    }

    inline fn opMod(self: *VM) void {
        const lhs = self.eval_stack.pop();
        const rhs = self.eval_stack.pop();
        self.eval_stack.push(.{
            .data = .{
                .integer = @mod(lhs.data.integer, rhs.data.integer),
            },
        });
    }

    inline fn opCall(self: *VM) void {
        const arg_count = self.nextByte();
        const func = self.eval_stack.pop();
        const frame = CallFrame{
            .func = self.current_func,
            .index = self.pc,
            .stack_offset = self.eval_stack.head - arg_count,
        };
        self.call_stack.push(frame);
        self.current_func = func.data.func;
        self.pc = 0;
    }

    inline fn opReturn(self: *VM) void {
        const is_return = self.nextByte() != 0;
        const call_frame = self.call_stack.pop();
        if (call_frame.root) {
            return;
        }
        self.current_func = call_frame.func;
        self.pc = call_frame.index;

        if (is_return) {
            const ret = self.eval_stack.pop();
            self.eval_stack.popFrame(call_frame.stack_offset);
            self.eval_stack.push(ret);
        } else {
            self.eval_stack.popFrame(call_frame.stack_offset);
        }
    }

    inline fn opCallBuiltin(self: *VM) void {
        const idx = self.nextByte();
        switch (idx) {
            0 => self.builtinPrint(),
            1 => self.builtinToString(),
            2 => self.builtinLength(),
            else => unreachable,
        }
    }

    inline fn opNegate(self: *VM) void {
        const item = self.eval_stack.pop();
        self.eval_stack.push(value.Value{ .data = .{ .boolean = !item.data.boolean } });
    }

    inline fn opEqual(self: *VM) void {
        const lhs = self.eval_stack.pop();
        const rhs = self.eval_stack.pop();
        self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.equals(rhs) } });
    }

    inline fn opGreaterThan(self: *VM) void {
        const lhs = self.eval_stack.pop();
        const rhs = self.eval_stack.pop();
        self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.data.integer > rhs.data.integer } });
    }

    inline fn opGreaterThanEquals(self: *VM) void {
        const lhs = self.eval_stack.pop();
        const rhs = self.eval_stack.pop();
        self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.data.integer >= rhs.data.integer } });
    }

    inline fn opLessThan(self: *VM) void {
        const lhs = self.eval_stack.pop();
        const rhs = self.eval_stack.pop();
        self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.data.integer < rhs.data.integer } });
    }

    inline fn opLessThanEquals(self: *VM) void {
        const lhs = self.eval_stack.pop();
        const rhs = self.eval_stack.pop();
        self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.data.integer <= rhs.data.integer } });
    }

    inline fn opAnd(self: *VM) void {
        const lhs = self.eval_stack.pop();
        const rhs = self.eval_stack.pop();
        self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.data.boolean and rhs.data.boolean } });
    }

    inline fn opOr(self: *VM) void {
        const lhs = self.eval_stack.pop();
        const rhs = self.eval_stack.pop();
        self.eval_stack.push(value.Value{ .data = .{ .boolean = lhs.data.boolean or rhs.data.boolean } });
    }

    inline fn opBranchNEQ(self: *VM) void {
        const offset = self.nextByte();
        const item = self.eval_stack.pop();
        if (!item.data.boolean) {
            self.pc += offset;
        }
    }

    inline fn opJump(self: *VM) void {
        const offset = self.nextByte();
        self.pc += offset;
    }

    inline fn opJumpBack(self: *VM) void {
        const offset = self.nextByte();
        self.pc -= offset;
    }

    inline fn opArrayInit(self: *VM) void {
        const items = self.nextByte();

        var array = std.ArrayListUnmanaged(value.Value).initCapacity(self.allocator, @intCast(items)) catch |err| {
            errorHandle(err);
            unreachable;
        };

        for (0..items) |_| {
            array.append(self.allocator, self.eval_stack.pop()) catch |err| {
                errorHandle(err);
                unreachable;
            };
        }

        const obj = self.garbage_collector.newObject();
        obj.* = .{
            .data = .{
                .array = .{
                    .items = array,
                },
            },
        };
        self.eval_stack.push(value.Value{ .data = .{ .object = obj } });
    }

    inline fn opArrayPush(self: *VM) void {
        const array_obj = self.eval_stack.pop();
        var array = &array_obj.data.object.data.array.items;
        const item = self.eval_stack.pop();
        array.append(self.allocator, item) catch |err| {
            errorHandle(err);
            unreachable;
        };
    }

    inline fn opArrayGet(self: *VM) void {
        const array_obj = self.eval_stack.pop();
        const array = &array_obj.data.object.data.array.items;
        const index_value = self.eval_stack.pop();
        const index: usize = @intCast(index_value.data.integer);
        if (array.items.len <= index) {
            errorHandle(Error.ArrayOutOfBounds);
            return;
        }
        self.eval_stack.push(array.items[index]);
    }

    inline fn opArraySet(self: *VM) void {
        const array_obj = self.eval_stack.pop();
        var array = &array_obj.data.object.data.array.items;
        const index_value = self.eval_stack.pop();
        const index: usize = @intCast(index_value.data.integer);
        const item = self.eval_stack.pop();
        if (array.items.len <= index) {
            errorHandle(Error.ArrayOutOfBounds);
            return;
        }
        array.items[index] = item;
    }

    inline fn builtinPrint(self: *VM) void {
        const item = self.eval_stack.pop();
        std.debug.print("{any}\n", .{item});
    }

    inline fn builtinToString(self: *VM) void {
        const item = self.eval_stack.pop();
        const raw = std.fmt.allocPrint(self.allocator, "{any}", .{item}) catch {
            return;
        };
        const object = self.garbage_collector.newObject();
        object.data = .{
            .string = .{
                .raw = raw,
            },
        };
        self.eval_stack.push(value.Value{ .data = .{ .object = object } });
    }

    inline fn builtinLength(self: *VM) void {
        const item = self.eval_stack.pop();
        const len = switch (item.data) {
            .object => |obj| blk: {
                switch (obj.data) {
                    .string => |string| break :blk string.raw.len,
                    .array => |array| break :blk array.items.items.len,
                }
            },
            else => unreachable,
        };
        self.eval_stack.push(value.Value{ .data = .{ .integer = @intCast(len) } });
    }

    /// Fetches the next byte and errors if there isn't one
    inline fn nextByte(self: *VM) u8 {
        if (self.pc >= self.bytes[self.current_func].len) {
            errorHandle(Error.MalformedInstruction);
        }
        const ret = self.bytes[self.current_func][self.pc];
        self.pc += 1;
        return ret;
    }
};
