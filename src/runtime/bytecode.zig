//! Runtime bytecode, handles all special cases like Opcodes

const std = @import("std");

pub const Opcode = enum(u8) {
    CONSTANT, // u8 constant index, pushes constant to stack
    VAR_SET, // u8 frame offset, pops value off of stack and assigns variable to it
    VAR_GET, // u8 frame offset, pushes value from variable onto stack
    STACK_ALLOC, // u8 amount of allocations to make, used to initialize memory for local variables
    ADD, // pops 2 values off of stack, pushes result after adding them
    SUB, // pops 2 values off of stack, pushes result after subtracting them
    MUL, // pops 2 values off of stack, pushes result after multiplying them
    DIV, // pops 2 values off of stack, pushes result after dividing them
    MOD, // pops 2 values off of stack, pushes result after modulus
    CALL, // u8 arg count
    RETURN, // u8 1 if there is a return value, 0 if not
    CALL_BUILTIN, // u8 builtin function number
    NEGATE, // pops 1 value off of stack, assumes boolean, negates and pushes result
    EQUAL, // pops 2 values off of stack, pushes boolean result after comparing
    GREATER_THAN, // pops 2 values off of stack, pushes boolean result after comparing
    GREATER_THAN_EQUALS, // pops 2 values off of stack, pushes boolean result after comparing,
    LESS_THAN, // pops 2 values off of stack, pushes boolean result after comparing
    LESS_THAN_EQUALS, // pops 2 values off of stack, pushes boolean result after comparing
    AND, // pops 2 values off of stack, assumes boolean, pushes boolean after comparing
    OR, // pops 2 values off of stack, assumes boolean, pushes boolean after comparing
    BRANCH_NEQ, // u8 offset, pops value off of stack, if false then jump to offset, otherwise nothing
    JUMP, // u8 offset
    ARRAY_INIT, // u8 item count, pops item count number of items off of stack and pushes initialized array
    ARRAY_PUSH, // pops two values off of stack, first is array second is item, pushes item to end of array
    ARRAY_GET, // pops two values off of stack, first is array, second is index, pushes indexed value or errors if out of bounds
    ARRAY_SET, // pops three values off of stack, first is array, second is index, third is value, sets index in array to value
};

pub fn dumpBytecode(funcs: [][]const u8) void {
    std.debug.print("--------------- DUMP ---------------\n", .{});
    for (0..funcs.len) |func_num| {
        const bytes = funcs[func_num];
        std.debug.print("Func #{d}:\n", .{func_num});
        var i: usize = 0;
        while (i < bytes.len) {
            const op: Opcode = @enumFromInt(bytes[i]);
            std.debug.print("    {s:<14} ", .{@tagName(op)});
            i += 1;
            switch (op) {
                .CONSTANT => {
                    std.debug.print("0x{X:0>2}\n", .{bytes[i]});
                    i += 1;
                },
                .VAR_SET => {
                    std.debug.print("0x{X:0>2}\n", .{bytes[i]});
                    i += 1;
                },
                .VAR_GET => {
                    std.debug.print("0x{X:0>2}\n", .{bytes[i]});
                    i += 1;
                },
                .STACK_ALLOC => {
                    std.debug.print("0x{X:0>2}\n", .{bytes[i]});
                    i += 1;
                },
                .ADD => {
                    std.debug.print("\n", .{});
                },
                .SUB => {
                    std.debug.print("\n", .{});
                },
                .MUL => {
                    std.debug.print("\n", .{});
                },
                .DIV => {
                    std.debug.print("\n", .{});
                },
                .MOD => {
                    std.debug.print("\n", .{});
                },
                .CALL => {
                    std.debug.print("0x{X:0>2}\n", .{bytes[i]});
                    i += 1;
                },
                .RETURN => {
                    std.debug.print("0x{X:0>2}\n", .{bytes[i]});
                    i += 1;
                },
                .CALL_BUILTIN => {
                    std.debug.print("0x{X:0>2}\n", .{bytes[i]});
                    i += 1;
                },
                .NEGATE => {
                    std.debug.print("\n", .{});
                },
                .EQUAL => {
                    std.debug.print("\n", .{});
                },
                .GREATER_THAN => {
                    std.debug.print("\n", .{});
                },
                .GREATER_THAN_EQUALS => {
                    std.debug.print("\n", .{});
                },
                .LESS_THAN => {
                    std.debug.print("\n", .{});
                },
                .LESS_THAN_EQUALS => {
                    std.debug.print("\n", .{});
                },
                .AND => {
                    std.debug.print("\n", .{});
                },
                .OR => {
                    std.debug.print("\n", .{});
                },
                .BRANCH_NEQ => {
                    std.debug.print("0x{X:0>2}\n", .{bytes[i]});
                    i += 1;
                },
                .JUMP => {
                    std.debug.print("0x{X:0>2}\n", .{bytes[i]});
                    i += 1;
                },
                .ARRAY_INIT => {
                    std.debug.print("0x{X:0>2}\n", .{bytes[i]});
                    i += 1;
                },
                .ARRAY_PUSH => {
                    std.debug.print("\n", .{});
                },
                .ARRAY_GET => {
                    std.debug.print("\n", .{});
                },
                .ARRAY_SET => {
                    std.debug.print("\n", .{});
                },
            }
        }
    }
    std.debug.print("------------------------------------\n", .{});
}
