//! Abstract Syntax Tree, used in passes and code generation

const std = @import("std");
const types = @import("types.zig");

pub const Operator = union(enum) {
    add,
    sub,
    mul,
    div,
    equals,
    not_equals,
    boolean_or,
    boolean_and,
    call: struct {
        args: std.ArrayListUnmanaged(*Node),
    },
    index: struct {
        index: *Node,
    },
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
        array_init: ArrayInit,
        block: Block,
        var_decl: VarDecl,
        var_assign: VarAssign,
        array_set: ArraySet,
        if_stmt: IfStatement,
        return_stmt: ReturnStatement,
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
        self_arg: bool = false,
        args: std.ArrayListUnmanaged(SymbolDecl) = std.ArrayListUnmanaged(SymbolDecl){},
        ret_type: types.Type,
        body: *Node,
    };

    const BuiltinCall = struct {
        idx: u8,
        args: []*Node,
    };

    const ArrayInit = struct {
        items: std.ArrayListUnmanaged(*Node) = std.ArrayListUnmanaged(*Node){},
    };

    const Block = struct {
        list: std.ArrayListUnmanaged(*Node) = std.ArrayListUnmanaged(*Node){},
    };

    const VarDecl = struct {
        symbol: SymbolDecl,
        expr: *Node,
    };

    const VarAssign = struct {
        name: []u8,
        expr: *Node,
    };

    const ArraySet = struct {
        array: *Node,
        index: *Node,
        expr: *Node,
    };

    const IfStatement = struct {
        expr: *Node,
        true_body: *Node,
        false_body: ?*Node,
    };

    const ReturnStatement = struct {
        expr: ?*Node,
    };
};
