//! Symbol population pass, resolves all symbols and links symbols to their declarations

const std = @import("std");
const ast = @import("../ast.zig");
const err = @import("../error.zig");
const types = @import("../types.zig");

pub const Error = error{
    SymbolNotFound,
    SymbolShadowing,
    TypeMismatch,
} || std.mem.Allocator.Error;

/// Helper to assist in scoping, allows user to obtain a "frame" and then later
/// pop everything in the stack that is after the frame.
const SymbolStack = struct {
    const Node = struct {
        next: ?*Node = null,
        prev: ?*Node = null,
        symbol: *ast.SymbolDecl,
    };
    self_arg: bool = false,
    allocator: std.mem.Allocator,
    front: ?*Node = null,

    pub fn deinit(self: *SymbolStack) void {
        while (self.front) |_| {
            _ = self.pop();
        }
    }

    pub fn getFrame(self: *SymbolStack) ?*Node {
        return self.front;
    }

    pub fn popFrame(self: *SymbolStack, maybe_frame: ?*Node) void {
        if (maybe_frame) |frame| {
            while (self.front != null and self.front.? != frame) {
                _ = self.pop();
            }
        } else {
            while (self.front != null) {
                _ = self.pop();
            }
        }
    }

    pub fn push(self: *SymbolStack, symbol: *ast.SymbolDecl) Error!void {
        const node = try self.allocator.create(Node);
        node.symbol = symbol;
        node.next = self.front;
        if (self.front) |front| {
            front.prev = node;
        }
        self.front = node;
    }

    pub fn pop(self: *SymbolStack) ?*ast.SymbolDecl {
        if (self.front) |front| {
            const node = front.symbol;
            self.front = front.next;
            return node;
        }
        return null;
    }

    /// Looks for a symbol in the stack. Fairly inefficient
    pub fn find(self: *SymbolStack, name: []const u8) ?*ast.SymbolDecl {
        var iter = self.front;
        while (iter) |node| {
            iter = node.next;
            if (std.mem.eql(u8, name, node.symbol.name)) {
                return node.symbol;
            }
        }
        return null;
    }
};

const Stack = struct {
    const Node = struct {
        next: ?*Node = null,
        data: SymbolStack,
    };
    head: ?*Node = null,

    pub fn push(self: *Stack, allocator: std.mem.Allocator, symbol_stack: SymbolStack) Error!*SymbolStack {
        const node = try allocator.create(Node);
        node.data = symbol_stack;
        node.next = self.head;
        self.head = node;
        return &node.data;
    }

    pub fn pop(self: *Stack) ?SymbolStack {
        if (self.head) |head| {
            const ret = head.data;
            self.head = head.next;
            return ret;
        } else {
            return null;
        }
    }

    pub fn peek(self: *Stack) ?*SymbolStack {
        if (self.head) |head| {
            return &head.data;
        }
        return null;
    }
};

pub const Pass = struct {
    stack_stack: Stack = Stack{}, // stack of stacks lol
    global_symbols: std.StringHashMapUnmanaged(*ast.SymbolDecl) = std.StringHashMapUnmanaged(*ast.SymbolDecl){},
    err_ctx: *err.ErrorContext,
    allocator: std.mem.Allocator,
    root: *ast.Node,

    pub fn init(allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, root: *ast.Node) Error!Pass {
        var pass = Pass{
            .err_ctx = err_ctx,
            .allocator = allocator,
            .root = root,
        };
        _ = try pass.stack_stack.push(allocator, SymbolStack{ .allocator = allocator });
        return pass;
    }

    pub fn run(self: *Pass) Error!void {
        try self.populateNode(self.root);
    }

    fn populateNode(self: *Pass, node: *ast.Node) Error!void {
        // Checking AST nodes that need a valid symbol
        const get_symbol: ?[]const u8 = switch (node.data) {
            .var_get => |var_get| var_get.name,
            .var_assign => |var_assign| var_assign.name,
            else => null,
        };
        if (get_symbol) |symbol| {
            if (self.global_symbols.get(symbol)) |found| {
                node.symbol_decl = found;
            } else if (self.stack_stack.peek().?.find(symbol)) |found| {
                node.symbol_decl = found;
            } else {
                try self.err_ctx.newError(.symbol_not_found, "Failed to locate symbol \"{s}\"", .{symbol}, node.index);
                return Error.SymbolNotFound;
            }
        }

        switch (node.data) {
            .int_constant => {},
            .boolean_constant => {},
            .string_constant => {},
            .var_get => |_| {},
            .block => |*block| {
                var stack = self.stack_stack.peek().?;
                const frame = stack.getFrame();
                for (block.list.items) |statement| {
                    try self.populateNode(statement);
                }
                stack.popFrame(frame);
            },
            .binary_op => |*binary| {
                try self.populateNode(binary.lhs);
                try self.populateNode(binary.rhs);
            },
            .unary_op => |*unary| {
                try self.populateNode(unary.expr);
                switch (unary.op) {
                    .call => |*call| {
                        for (call.args.items) |arg| {
                            try self.populateNode(arg);
                        }
                    },
                    .index => |*index| {
                        try self.populateNode(index.index);
                        try self.populateNode(unary.expr);
                    },
                    else => unreachable,
                }
            },
            .function_value => |*func| {
                var stack = try self.stack_stack.push(self.allocator, SymbolStack{ .allocator = self.allocator, .self_arg = func.self_arg });
                for (func.args.items) |*arg| {
                    try stack.push(arg);
                }
                if (func.name) |name| {
                    const symbol = try self.allocator.create(ast.SymbolDecl);
                    symbol.* = ast.SymbolDecl{ .name = name, .function_decl = node };
                    try self.global_symbols.put(self.allocator, name, symbol);
                }
                if (func.self_arg) {
                    const symbol = try self.allocator.create(ast.SymbolDecl);
                    symbol.* = ast.SymbolDecl{ .name = try self.allocator.dupe(u8, "self"), .function_decl = node };
                    try stack.push(symbol);
                }
                try self.populateNode(func.body);
                var ret = self.stack_stack.pop();
                ret.?.deinit();
            },
            .builtin_call => |*call| {
                for (call.args) |arg| {
                    try self.populateNode(arg);
                }
            },
            .array_init => |*array| {
                for (array.items.items) |item| {
                    try self.populateNode(item);
                }
            },
            .var_decl => |*var_decl| {
                var stack = self.stack_stack.peek().?;
                if (stack.find(var_decl.symbol.name)) |_| {
                    try self.err_ctx.newError(.symbol_shadowing, "Found symbol shadowing previous declaration, \"{s}\"", .{var_decl.symbol.name}, node.index);
                    return Error.SymbolShadowing;
                }
                try stack.push(&var_decl.symbol);
                try self.populateNode(var_decl.expr);
            },
            .var_assign => |*var_assign| try self.populateNode(var_assign.expr),
            .while_loop => |*while_loop| {
                try self.populateNode(while_loop.expr);
                try self.populateNode(while_loop.body);
            },
            .for_loop => |*for_loop| {
                var stack = self.stack_stack.peek().?;
                const frame = stack.getFrame();
                try self.populateNode(for_loop.init);
                try self.populateNode(for_loop.condition);
                try self.populateNode(for_loop.after);
                try self.populateNode(for_loop.body);
                stack.popFrame(frame);
            },
            .array_set => |*array_set| {
                try self.populateNode(array_set.index);
                try self.populateNode(array_set.expr);
                try self.populateNode(array_set.array);
            },
            .if_stmt => |*if_stmt| {
                try self.populateNode(if_stmt.expr);
                try self.populateNode(if_stmt.true_body);
                if (if_stmt.false_body) |false_body| {
                    try self.populateNode(false_body);
                }
            },
            .return_stmt => |*ret| {
                if (ret.expr) |expr| {
                    try self.populateNode(expr);
                }
            },
        }
    }
};
