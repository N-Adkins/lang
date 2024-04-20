//! Runtime value data, universal tagged union for any variable / constant

const std = @import("std");
const gc = @import("gc.zig");

// data must be 8 bytes or lower
pub const Value = struct {
    data: union(enum) {
        number: i64,
        func: usize, // func table index
        object: *gc.Object,
    },
};

test "Value Word Size" {
    try std.testing.expect(@sizeOf(Value) <= @sizeOf(*anyopaque));
}
