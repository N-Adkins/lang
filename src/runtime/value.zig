const std = @import("std");

// data must be 8 bytes or lower
pub const Value = struct {
    data: union(enum) {
        number: i64,
        uninitialized: void, // only to be used by compiler guaranteed memory, like stack memory for initialized vars
    },
};
