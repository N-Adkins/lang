//! Runtime value data, universal tagged union for any variable / constant

const std = @import("std");
const gc = @import("gc.zig");

// data must be 8 bytes or lower
pub const Value = struct {
    data: union(enum) {
        number: f64,
        func: usize, // func table index
        object: *gc.Object,
    },

    pub fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        switch (self.data) {
            .number => |number| try writer.print("[Number {d}]", .{number}),
            .func => |func| try writer.print("[Function {d}]", .{func}),
            .object => |_| try writer.print("[Object object]", .{}),
        }
    }
};

test "Value Word Size" {
    try std.testing.expect(@sizeOf(Value) <= @sizeOf(*anyopaque));
}
