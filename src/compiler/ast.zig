//! Abstract Syntax Tree, used in passes and code generation

const std = @import("std");
const types = @import("types.zig");

pub const Operator = union(enum) {
    add,
    sub,
    mul,
    div,
    call: struct { args: std.ArrayListUnmanaged(*Node) },

    pub fn deinit(self: *Operator, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .call => |*call| {
                for (call.args.items) |arg| {
                    arg.deinit(allocator);
                    allocator.destroy(arg);
                }
                call.args.deinit(allocator);
            },
            else => {},
        }
    }
};

pub const SymbolDecl = struct {
    name: []const u8,
    decl_type: ?types.Type,

    pub fn deinit(self: *SymbolDecl, allocator: std.mem.Allocator) void {
        if (self.decl_type) |*decl_type| {
            decl_type.deinit(allocator);
        }
        allocator.free(self.name);
    }
};

/// Abstract Syntax Tree Node, contains both
/// statements and expressions
pub const Node = struct {
    symbol_decl: ?*SymbolDecl = null,
    index: usize,
    data: union(enum) {
        integer_constant: IntegerConstant,
        var_get: VarGet,
        unary_op: UnaryOp,
        binary_op: BinaryOp,
        function_decl: FunctionDecl,
        block: Block,
        var_decl: VarDecl,
        var_assign: VarAssign,
        return_stmt: Return,
    },

    const IntegerConstant = struct {
        value: i64,
    };

    const VarGet = struct {
        name: []u8,

        pub fn deinit(self: *VarGet, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
        }
    };

    const UnaryOp = struct {
        op: Operator,
        expr: *Node,

        pub fn deinit(self: *UnaryOp, allocator: std.mem.Allocator) void {
            switch (self.op) {
                .call => |*call| {
                    for (call.args.items) |arg| {
                        arg.deinit(allocator);
                        allocator.destroy(arg);
                    }
                    call.args.deinit(allocator);
                },
                else => unreachable,
            }
            self.expr.deinit(allocator);
            allocator.destroy(self.expr);
        }
    };

    const BinaryOp = struct {
        op: Operator,
        lhs: *Node,
        rhs: *Node,

        pub fn deinit(self: *BinaryOp, allocator: std.mem.Allocator) void {
            self.lhs.deinit(allocator);
            self.rhs.deinit(allocator);
            allocator.destroy(self.lhs);
            allocator.destroy(self.rhs);
        }
    };

    const FunctionDecl = struct {
        args: std.ArrayListUnmanaged(SymbolDecl),
        ret_type: types.Type,
        body: *Node,

        pub fn deinit(self: *FunctionDecl, allocator: std.mem.Allocator) void {
            for (self.args.items) |*arg| {
                arg.deinit(allocator);
            }
            self.args.deinit(allocator);
            self.ret_type.deinit(allocator);
            self.body.deinit(allocator);
            allocator.destroy(self.body);
        }
    };

    const Block = struct {
        list: std.ArrayListUnmanaged(*Node),

        pub fn deinit(self: *Block, allocator: std.mem.Allocator) void {
            for (self.list.items) |statement| {
                statement.deinit(allocator);
                allocator.destroy(statement);
            }
            self.list.deinit(allocator);
        }
    };

    const VarDecl = struct {
        symbol: SymbolDecl,
        expr: *Node,

        pub fn deinit(self: *VarDecl, allocator: std.mem.Allocator) void {
            self.symbol.deinit(allocator);
            self.expr.deinit(allocator);
            allocator.destroy(self.expr);
        }
    };

    const VarAssign = struct {
        name: []u8,
        expr: *Node,

        pub fn deinit(self: *VarAssign, allocator: std.mem.Allocator) void {
            self.expr.deinit(allocator);
            allocator.destroy(self.expr);
            allocator.free(self.name);
        }
    };

    const Return = struct {
        expr: ?*Node,

        pub fn deinit(self: *Return, allocator: std.mem.Allocator) void {
            if (self.expr) |expr| {
                expr.deinit(allocator);
                allocator.destroy(expr);
            }
        }
    };

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.data) {
            inline else => |*e| {
                if (std.meta.hasMethod(@TypeOf(e), "deinit")) {
                    e.deinit(allocator);
                }
            },
        }
    }
};
