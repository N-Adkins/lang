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
    CALL, // u8 argument count
    RETURN, // u8 1 if return value, 0 if none
};

pub fn dumpBytecode(funcs: [][]const u8) void {
    for (0..funcs.len) |func_num| {
        const bytes = funcs[func_num];
        std.debug.print("Func #{d}:\n", .{func_num});
        var i: usize = 0;
        while (i < bytes.len) {
            const op: Opcode = @enumFromInt(bytes[i]);
            std.debug.print("    {s} ", .{@tagName(op)});
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
                .CALL => {
                    std.debug.print("0x{X:0>2}\n", .{bytes[i]});
                    i += 1;
                },
                .RETURN => {
                    std.debug.print("0x{X:0>2}\n", .{bytes[i]});
                    i += 1;
                },
            }
        }
    }
}
