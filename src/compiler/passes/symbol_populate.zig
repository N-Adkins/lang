const std = @import("std");
const ast = @import("../ast.zig");
const err = @import("../error.zig");
const types = @import("../types.zig");

pub const SymbolPassError = error{
    SymbolNotFound,
    SymbolShadowing,
    TypeMismatch,
} || std.mem.Allocator.Error;

const SymbolStack = struct {
    const Node = struct {
        next: ?*Node = null,
        prev: ?*Node = null,
        symbol: *ast.AstNode,
    };
    allocator: std.mem.Allocator,
    front: ?*Node = null,

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

    pub fn push(self: *SymbolStack, symbol: *ast.AstNode) SymbolPassError!void {
        const node = try self.allocator.create(Node);
        node.symbol = symbol;
        node.next = self.front;
        if (self.front) |front| {
            front.prev = node;
        }
        self.front = node;
    }

    pub fn pop(self: *SymbolStack) ?*ast.AstNode {
        if (self.front) |front| {
            const node = front.symbol;
            self.front = front.next;
            self.allocator.destroy(front);
            return node;
        }
        return null;
    }

    pub fn find(self: *SymbolStack, name: []const u8) ?*ast.AstNode {
        var iter = self.front;
        while (iter) |node| {
            iter = node.next;
            const str: ?[]const u8 = switch (node.symbol.data) {
                .var_decl => |var_assign| var_assign.name,
                else => null,
            };
            if (str) |slice| {
                if (std.mem.eql(u8, name, slice)) {
                    return node.symbol;
                }
            }
        }
        return null;
    }
};

// Naive stack implementation for now, can swap to tree or map later on
pub const SymbolPass = struct {
    err_ctx: *err.ErrorContext,
    allocator: std.mem.Allocator,
    stack: SymbolStack,
    root: *ast.AstNode,

    pub fn init(allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, root: *ast.AstNode) SymbolPass {
        return SymbolPass{
            .err_ctx = err_ctx,
            .allocator = allocator,
            .stack = SymbolStack{ .allocator = allocator },
            .root = root,
        };
    }

    pub fn deinit(self: *SymbolPass) void {
        while (self.stack.pop()) |_| {}
    }

    pub fn run(self: *SymbolPass) SymbolPassError!void {
        try self.populateNode(self.root);
    }

    fn populateNode(self: *SymbolPass, node: *ast.AstNode) SymbolPassError!void {
        // Checking AST nodes that need a valid symbol
        const get_symbol: ?[]const u8 = switch (node.data) {
            .var_get => |var_get| var_get.name,
            .var_assign => |var_assign| var_assign.name,
            else => null,
        };
        if (get_symbol) |symbol| {
            if (self.stack.find(symbol)) |found| {
                node.symbol_decl = found;
            } else {
                try self.err_ctx.newError(.symbol_not_found, "Failed to locate symbol \"{s}\"", .{symbol}, node.index);
                return SymbolPassError.SymbolNotFound;
            }
        }

        switch (node.data) {
            .integer_constant => {},
            .var_get => |_| {},
            .block => |block| {
                const frame = self.stack.getFrame();
                for (block.list.items) |statement| {
                    try self.populateNode(statement);
                }
                self.stack.popFrame(frame);
            },
            .var_decl => |var_decl| {
                if (self.stack.find(var_decl.name)) |_| {
                    try self.err_ctx.newError(.symbol_shadowing, "Found symbol shadowing previous declaration, \"{s}\"", .{var_decl.name}, node.index);
                    return SymbolPassError.SymbolShadowing;
                }
                try self.stack.push(node);
                try self.populateNode(var_decl.expr);
            },
            .var_assign => |var_assign| try self.populateNode(var_assign.expr),
        }
    }
};