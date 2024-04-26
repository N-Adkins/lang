//! Code Generation Pass, converts AST into bytecode and a constant table.
const std = @import("std");
const ast = @import("../ast.zig");
const byte = @import("../../runtime/bytecode.zig");
const err = @import("../error.zig");
const value = @import("../../runtime/value.zig");

pub const Error = error{
    ConstantOverflow,
    LocalOverflow,
} || std.mem.Allocator.Error;

/// Used in function stack to figure out how many local variables are in each stack frame.
/// Later on this becomes a STACK_ALLOC instruction to reserve local variable space.
const FuncFrame = struct {
    func: usize,
    local_count: u8 = 0,
    map: std.AutoHashMapUnmanaged(*anyopaque, u8) = std.AutoHashMapUnmanaged(*anyopaque, u8){},
};

const ByteFunc = struct {
    code: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
};

pub const Pass = struct {
    const FrameNode = std.DoublyLinkedList(FuncFrame).Node;
    func_stack: std.DoublyLinkedList(FuncFrame) = std.DoublyLinkedList(FuncFrame){},
    bytecode: std.ArrayListUnmanaged(ByteFunc) = std.ArrayListUnmanaged(ByteFunc){},
    constants: std.ArrayListUnmanaged(value.Value) = std.ArrayListUnmanaged(value.Value){},
    func_count: usize = 0,
    root: *ast.Node,
    err_ctx: *err.ErrorContext,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, root: *ast.Node) Error!Pass {
        return Pass{
            .root = root,
            .err_ctx = err_ctx,
            .allocator = allocator,
        };
    }

    pub fn run(self: *Pass) Error!void {
        _ = try self.genFunc(self.root, null);
    }

    /// Wrapper over genNode but with handling local variable allocation
    fn genFunc(self: *Pass, body: *ast.Node, call_func: ?*ast.Node) Error!usize {
        _ = try self.pushFrame();
        _ = try self.pushOp(.STACK_ALLOC);
        const alloc_count = self.bytecode.items[self.func_stack.first.?.data.func].code.items.len;
        _ = try self.pushByte(0); // temp
        if (call_func) |func| {
            const decl = func.data.function_value;
            for (decl.args.items) |*arg| {
                _ = try self.pushLocal(arg);
            }
        }
        const frame = &self.func_stack.first.?.data;
        if (call_func) |func| {
            func.data.function_value.func_idx = frame.func;
        }
        try self.genNode(body);
        self.bytecode.items[frame.func].code.items[alloc_count] = frame.local_count;
        self.popFrame();
        return frame.func;
    }

    fn genNode(self: *Pass, node: *ast.Node) Error!void {
        switch (node.data) {
            .int_constant => |*int| {
                try self.pushConstant(value.Value{ .data = .{ .integer = int.value } });
            },
            .boolean_constant => |*boolean| {
                try self.pushConstant(value.Value{ .data = .{ .boolean = boolean.value } });
            },
            .string_constant => |*str| {
                const object = try self.allocator.create(value.Object);
                object.data = .{
                    .string = .{
                        .raw = try self.allocator.dupe(u8, str.raw),
                    },
                };
                try self.pushConstant(value.Value{ .data = .{ .object = object } });
            },
            .var_get => |_| {
                if (node.symbol_decl.?.function_decl) |func| {
                    try self.pushConstant(value.Value{ .data = .{ .func = func.data.function_value.func_idx } });
                    return;
                }
                const decl = node.symbol_decl.?;
                const index = try self.getLocal(decl);
                try self.pushOp(.VAR_GET);
                try self.pushByte(index);
            },
            .binary_op => |*binary| {
                const op: byte.Opcode = switch (binary.op) {
                    .add => .ADD,
                    .sub => .SUB,
                    .mul => .MUL,
                    .div => .DIV,
                    .mod => .MOD,
                    .boolean_and => .AND,
                    .boolean_or => .OR,
                    .equals => .EQUAL,
                    .not_equals => {
                        try self.genNode(binary.lhs);
                        try self.genNode(binary.rhs);
                        try self.pushOp(.EQUAL);
                        try self.pushOp(.NEGATE);
                        return;
                    },
                    .greater_than => .GREATER,
                    .greater_than_equals => .GREATER_EQ,
                    .less_than => .LESS,
                    .less_than_equals => .LESS_EQ,
                    else => unreachable,
                };
                try self.genNode(binary.rhs);
                try self.genNode(binary.lhs);
                try self.pushOp(op);
            },
            .unary_op => |*unary| {
                switch (unary.op) {
                    .call => |call| {
                        for (call.args.items) |expr| {
                            try self.genNode(expr);
                        }
                        try self.genNode(unary.expr);
                        try self.pushOp(.CALL);
                        try self.pushByte(@truncate(call.args.items.len));
                    },
                    .index => |index| {
                        try self.genNode(index.index);
                        try self.genNode(unary.expr);
                        try self.pushOp(.ARRAY_GET);
                    },
                    else => unreachable,
                }
            },
            .function_value => |*func| {
                const func_code = try self.genFunc(func.body, node);
                try self.pushConstant(value.Value{
                    .data = .{
                        .func = func_code,
                    },
                });
            },
            .builtin_call => |*call| {
                for (call.args) |arg| {
                    try self.genNode(arg);
                }
                try self.pushOp(.CALL_BUILTIN);
                try self.pushByte(call.idx);
            },
            .array_init => |*array| {
                // in reverse so they're popped off in order
                var i: usize = array.items.items.len;
                while (i > 0) {
                    i -= 1;
                    try self.genNode(array.items.items[i]);
                }
                try self.pushOp(.ARRAY_INIT);
                try self.pushByte(@truncate(array.items.items.len));
            },
            .block => |*block| {
                for (block.list.items) |statement| {
                    try self.genNode(statement);
                }
            },
            .var_decl => |*var_decl| {
                const index = try self.pushLocal(&var_decl.symbol);
                try self.genNode(var_decl.expr);
                try self.pushOp(.VAR_SET);
                try self.pushByte(index);
            },
            .var_assign => |*var_assign| {
                const decl = node.symbol_decl.?;
                const index = try self.getLocal(decl);
                try self.genNode(var_assign.expr);
                try self.pushOp(.VAR_SET);
                try self.pushByte(index);
            },
            .while_loop => |*while_loop| {
                const frame = &self.func_stack.first.?.data;
                const func = &self.bytecode.items[frame.func].code;
                const before_condition = func.items.len;
                try self.genNode(while_loop.expr);
                try self.pushOp(.BRANCH_NEQ);
                const branch_byte = func.items.len;
                try self.pushByte(0); // placeholder
                try self.genNode(while_loop.body);
                const after_body = func.items.len;
                const jump_distance: u8 = @as(u8, @truncate(after_body - before_condition)) + 2;
                const branch_distance: u8 = @as(u8, @truncate(after_body - branch_byte)) + 1;
                func.items[branch_byte] = branch_distance;
                try self.pushOp(.JUMP_BACK);
                try self.pushByte(jump_distance);
            },
            .for_loop => |*for_loop| {
                const frame = &self.func_stack.first.?.data;
                const func = &self.bytecode.items[frame.func].code;
                try self.genNode(for_loop.init);
                const before_condition = func.items.len;
                try self.genNode(for_loop.condition);
                try self.pushOp(.BRANCH_NEQ);
                const branch_byte = func.items.len;
                try self.pushByte(0); // placeholder
                try self.genNode(for_loop.body);
                try self.genNode(for_loop.after);
                const after_body = func.items.len;
                const jump_distance: u8 = @as(u8, @truncate(after_body - before_condition)) + 2;
                const branch_distance: u8 = @as(u8, @truncate(after_body - branch_byte)) + 1;
                func.items[branch_byte] = branch_distance;
                try self.pushOp(.JUMP_BACK);
                try self.pushByte(jump_distance);
            },
            .array_set => |*array_set| {
                try self.genNode(array_set.expr);
                try self.genNode(array_set.index);
                try self.genNode(array_set.array);
                try self.pushOp(.ARRAY_SET);
            },
            .if_stmt => |*if_stmt| {
                try self.genNode(if_stmt.expr);
                try self.pushOp(.BRANCH_NEQ);

                const func = self.func_stack.first.?.data.func;
                const start = self.bytecode.items[func].code.items.len;
                try self.pushByte(0); // temp

                try self.genNode(if_stmt.true_body);

                const offset = self.bytecode.items[func].code.items.len - start - 1;
                self.bytecode.items[func].code.items[start] = @truncate(offset);

                if (if_stmt.false_body) |false_body| {
                    self.bytecode.items[func].code.items[start] += 2;
                    try self.pushOp(.JUMP);
                    const false_start = self.bytecode.items[func].code.items.len;
                    try self.pushByte(0); // temp
                    try self.genNode(false_body);
                    const false_offset = self.bytecode.items[func].code.items.len - false_start - 1;
                    self.bytecode.items[func].code.items[false_start] = @truncate(false_offset);
                }
            },
            .return_stmt => |*ret| {
                const is_value: u8 = if (ret.expr) |expr| blk: {
                    try self.genNode(expr);
                    break :blk 1;
                } else 0;
                try self.pushOp(.RETURN);
                try self.pushByte(is_value);
            },
        }
    }

    /// Pushes a byte into the bytecode
    fn pushByte(self: *Pass, item: u8) Error!void {
        const func = self.func_stack.first.?.data.func;
        try self.bytecode.items[func].code.append(self.allocator, item);
    }

    /// Pushes an opcode into the bytecode as a byte
    fn pushOp(self: *Pass, op: byte.Opcode) Error!void {
        const func = self.func_stack.first.?.data.func;
        try self.bytecode.items[func].code.append(self.allocator, @intFromEnum(op));
    }

    /// Pushes a constant onto the constant table
    fn pushConstant(self: *Pass, item: value.Value) Error!void {
        if (self.constants.items.len >= 0xFF) {
            try self.err_ctx.newError(.constant_overflow, "Number of constants exceeds 0xFF", .{}, null);
            return Error.ConstantOverflow;
        }
        const index = self.constants.items.len;
        try self.constants.append(self.allocator, item);
        try self.pushOp(.CONSTANT);
        try self.pushByte(@truncate(index));
    }

    /// Pushes a local variable onto the current function frame
    fn pushLocal(self: *Pass, decl: *ast.SymbolDecl) Error!u8 {
        const head = self.func_stack.first.?;
        const index = head.data.local_count;
        try head.data.map.put(self.allocator, @ptrCast(decl), index);
        if (head.data.local_count +% 1 < head.data.local_count) {
            try self.err_ctx.newError(.local_overflow, "Number of locals exceeds 0xFF", .{}, null);
            return Error.ConstantOverflow;
        }
        head.data.local_count += 1;
        return index;
    }

    /// Checks the current function frame for a local variable based on its
    /// declaration
    fn getLocal(self: *Pass, decl: *ast.SymbolDecl) Error!u8 {
        const head = self.func_stack.first.?;
        const index = head.data.map.get(@ptrCast(decl)).?;
        return index;
    }

    /// Pushes a new function frame
    fn pushFrame(self: *Pass) Error!*FuncFrame {
        const main_node = try self.allocator.create(FrameNode);
        main_node.data = FuncFrame{
            .func = self.func_count,
        };
        try self.bytecode.append(self.allocator, ByteFunc{});
        self.func_count += 1;
        self.func_stack.prepend(main_node);
        return &self.func_stack.first.?.data;
    }

    /// Pops a function frame
    fn popFrame(self: *Pass) void {
        const head = self.func_stack.popFirst().?;
        self.allocator.destroy(head);
    }
};
