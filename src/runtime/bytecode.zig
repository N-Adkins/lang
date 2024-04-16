const std = @import("std");

pub const Opcode = enum(u8) {
    CONSTANT, // Push value from constant table
};
