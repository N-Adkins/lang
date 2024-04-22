//! Abstract Syntax Tree, used in passes and code generation

const std = @import("std");
const types = @import("types.zig");

pub const Operator = union(enum) {
    add,
    sub,
    mul,
    div,
    bool_not_equal,
    bool_equal,
    bool_or,
    bool_and,
    call: struct { args: std.ArrayListUnmanaged(*Node) },
};

pub const SymbolDecl = struct {
    name: []const u8,
    decl_type: ?types.Type,
};

/// Abstract Syntax Tree Node, contains both
/// statements and expressions
pub const Node = struct {
    symbol_decl: ?*SymbolDecl = null,
    index: usize,
    data: union(enum) {
        number_constant: NumberConstant,
        boolean_constant: BooleanConstant,
        string_constant: StringConstant,
        var_get: VarGet,
        unary_op: UnaryOp,
        binary_op: BinaryOp,
        function_decl: FunctionDecl,
        builtin_call: BuiltinCall,
        block: Block,
        var_decl: VarDecl,
        var_assign: VarAssign,
        return_stmt: Return,
    },

    const NumberConstant = struct {
        value: f64,
    };

    const BooleanConstant = struct {
        value: bool,
    };

    const StringConstant = struct {
        raw: []const u8,
    };

    const VarGet = struct {
        name: []u8,
    };

    const UnaryOp = struct {
        op: Operator,
        expr: *Node,
    };

    const BinaryOp = struct {
        op: Operator,
        lhs: *Node,
        rhs: *Node,
    };

    const FunctionDecl = struct {
        args: std.ArrayListUnmanaged(SymbolDecl),
        ret_type: types.Type,
        body: *Node,
    };

    const BuiltinCall = struct {
        idx: u8,
        args: []*Node,
    };

    const Block = struct {
        list: std.ArrayListUnmanaged(*Node),
    };

    const VarDecl = struct {
        symbol: SymbolDecl,
        expr: *Node,
    };

    const VarAssign = struct {
        name: []u8,
        expr: *Node,
    };

    const Return = struct {
        expr: ?*Node,
    };
};
