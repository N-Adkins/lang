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
    byte_start: usize,
    local_count: u8 = 0,
    map: std.AutoHashMapUnmanaged(*anyopaque, u8) = std.AutoHashMapUnmanaged(*anyopaque, u8){},
};

pub const Pass = struct {
    const FrameNode = std.DoublyLinkedList(FuncFrame).Node;
    func_stack: std.DoublyLinkedList(FuncFrame) = std.DoublyLinkedList(FuncFrame){},
    bytecode: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
    constants: std.ArrayListUnmanaged(value.Value) = std.ArrayListUnmanaged(value.Value){},
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

    pub fn deinit(self: *Pass) void {
        while (self.func_stack.first) |_| {
            self.popFrame();
        }
        self.bytecode.deinit(self.allocator);
        self.constants.deinit(self.allocator);
    }

    pub fn run(self: *Pass) Error!void {
        try self.genFunc(self.root);
    }

    /// Wrapper over genNode but with handling local variable allocation
    fn genFunc(self: *Pass, body: *ast.Node) Error!void {
        _ = try self.pushFrame();
        try self.genNode(body);
        const frame = self.func_stack.first.?.data;
        const stack_alloc = &[2]u8{ @intFromEnum(byte.Opcode.STACK_ALLOC), frame.local_count };
        try self.bytecode.insertSlice(self.allocator, frame.byte_start, stack_alloc);
        self.popFrame();
    }

    fn genNode(self: *Pass, node: *ast.Node) Error!void {
        switch (node.data) {
            .integer_constant => |int_constant| {
                try self.pushConstant(value.Value{ .data = .{ .number = int_constant.value } });
            },
            .var_get => |_| {
                const decl = node.symbol_decl.?;
                const index = try self.getLocal(decl);
                try self.pushOp(.VAR_GET);
                try self.pushByte(index);
            },
            .binary_op => |binary| {
                const op: byte.Opcode = switch (binary.op) {
                    .add => .ADD,
                    .sub => .SUB,
                    .mul => .MUL,
                    .div => .DIV,
                };
                try self.genNode(binary.lhs);
                try self.genNode(binary.rhs);
                try self.pushOp(op);
            },
            .unary_op => |_| {},
            .block => |block| {
                for (block.list.items) |statement| {
                    try self.genNode(statement);
                }
            },
            .var_decl => |var_decl| {
                const index = try self.pushLocal(node);
                try self.genNode(var_decl.expr);
                try self.pushOp(.VAR_SET);
                try self.pushByte(index);
            },
            .var_assign => |var_assign| {
                const decl = node.symbol_decl.?;
                const index = try self.getLocal(decl);
                try self.genNode(var_assign.expr);
                try self.pushOp(.VAR_SET);
                try self.pushByte(index);
            },
        }
    }

    /// Pushes a byte into the bytecode
    fn pushByte(self: *Pass, item: u8) Error!void {
        try self.bytecode.append(self.allocator, item);
    }

    /// Pushes an opcode into the bytecode as a byte
    fn pushOp(self: *Pass, op: byte.Opcode) Error!void {
        try self.bytecode.append(self.allocator, @intFromEnum(op));
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
    fn pushLocal(self: *Pass, decl: *ast.Node) Error!u8 {
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
    fn getLocal(self: *Pass, decl: *ast.Node) Error!u8 {
        const head = self.func_stack.first.?;
        const index = head.data.map.get(@ptrCast(decl)).?;
        return index;
    }

    /// Pushes a new function frame
    fn pushFrame(self: *Pass) Error!*FuncFrame {
        const main_node = try self.allocator.create(FrameNode);
        main_node.data = FuncFrame{
            .byte_start = self.bytecode.items.len,
        };
        self.func_stack.prepend(main_node);
        return &self.func_stack.first.?.data;
    }

    /// Pops a function frame
    fn popFrame(self: *Pass) void {
        const head = self.func_stack.popFirst().?;
        head.data.map.deinit(self.allocator);
        self.allocator.destroy(head);
    }
};
