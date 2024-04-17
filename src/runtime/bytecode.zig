const std = @import("std");

pub const Opcode = enum(u8) {
    CONSTANT, // u8 constant index
    VAR_SET, // u8 frame offset
    VAR_GET, // u8 frame offset
};

pub fn dumpBytecode(bytes: []const u8) void {
    var i: usize = 0;
    while (i < bytes.len) {
        const op: Opcode = @enumFromInt(bytes[i]);
        std.debug.print("{s} ", .{@tagName(op)});
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
        }
    }
}
