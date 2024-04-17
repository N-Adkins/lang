const std = @import("std");

pub const Opcode = enum(u8) {
    CONSTANT, // u8 constant index
    VAR_SET, // u8 frame offset
    VAR_GET, // u8 frame offset
};
