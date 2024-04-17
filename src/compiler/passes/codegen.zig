const std = @import("std");
const ast = @import("../ast.zig");
const byte = @import("../../runtime/bytecode.zig");
const err = @import("../error.zig");
const value = @import("../../runtime/value.zig");

pub const GenError = error{
    ConstantOverflow,
    LocalOverflow,
} || std.mem.Allocator.Error;

const FuncFrame = struct {
    local_count: u8 = 0,
    map: std.AutoHashMapUnmanaged(*anyopaque, u8) = std.AutoHashMapUnmanaged(*anyopaque, u8){},
};

pub const CodeGenPass = struct {
    const FrameNode = std.DoublyLinkedList(FuncFrame).Node;
    func_stack: std.DoublyLinkedList(FuncFrame) = std.DoublyLinkedList(FuncFrame){},
    bytecode: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
    constants: std.ArrayListUnmanaged(value.Value) = std.ArrayListUnmanaged(value.Value){},
    root: *ast.AstNode,
    err_ctx: *err.ErrorContext,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, root: *ast.AstNode) GenError!CodeGenPass {
        var pass = CodeGenPass{
            .root = root,
            .err_ctx = err_ctx,
            .allocator = allocator,
        };
        _ = try pass.pushFrame();
        return pass;
    }

    pub fn deinit(self: *CodeGenPass) void {
        while (self.func_stack.first) |_| {
            self.popFrame();
        }
        self.bytecode.deinit(self.allocator);
        self.constants.deinit(self.allocator);
    }

    pub fn run(self: *CodeGenPass) GenError!void {
        try self.genNode(self.root);
    }

    fn genNode(self: *CodeGenPass, node: *ast.AstNode) GenError!void {
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

    fn pushByte(self: *CodeGenPass, item: u8) GenError!void {
        try self.bytecode.append(self.allocator, item);
    }

    fn pushOp(self: *CodeGenPass, op: byte.Opcode) GenError!void {
        try self.bytecode.append(self.allocator, @intFromEnum(op));
    }

    fn pushConstant(self: *CodeGenPass, item: value.Value) GenError!void {
        if (self.constants.items.len >= 0xFF) {
            try self.err_ctx.newError(.constant_overflow, "Number of constants exceeds 0xFF", .{}, null);
            return GenError.ConstantOverflow;
        }
        const index = self.constants.items.len;
        try self.constants.append(self.allocator, item);
        try self.pushOp(.CONSTANT);
        try self.pushByte(@truncate(index));
    }
    
    fn pushLocal(self: *CodeGenPass, decl: *ast.AstNode) GenError!u8 {
        const head = self.func_stack.first.?; 
        const index = head.data.local_count;
        try head.data.map.put(self.allocator, @ptrCast(decl), index);
        if (head.data.local_count +% 1 < head.data.local_count) {
            try self.err_ctx.newError(.local_overflow, "Number of locals exceeds 0xFF", .{}, null);
            return GenError.ConstantOverflow;
        }
        head.data.local_count += 1;
        return index;
    }
    
    fn getLocal(self: *CodeGenPass, decl: *ast.AstNode) GenError!u8 {
        const head = self.func_stack.first.?;
        const index = head.data.map.get(@ptrCast(decl)).?;
        return index;
    }

    fn pushFrame(self: *CodeGenPass) GenError!*FuncFrame {
        const main_node = try self.allocator.create(FrameNode);
        main_node.data = FuncFrame{};
        self.func_stack.prepend(main_node);
        return &self.func_stack.first.?.data;
    }

    fn popFrame(self: *CodeGenPass) void {
        const head = self.func_stack.popFirst().?;
        head.data.map.deinit(self.allocator);
        self.allocator.destroy(head);
    }
};
