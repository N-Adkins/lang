//! Runtime value data, universal tagged union for any variable / constant

const std = @import("std");

/// Object Interface
pub const Object = struct {
    ptr: *anyopaque,
    vtable: struct {
        deinit: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
    },

    pub fn init(init_ptr: anytype, init_allocator: std.mem.Allocator) std.mem.Allocator.Error!*Object {
        const vtable_gen = struct {
            fn deinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self: @TypeOf(ptr) = @ptrCast(@alignCast(ptr));
                return self.deinit(allocator);
            }
        };

        const obj = try init_allocator.create(Object);
        obj.* = .{
            .ptr = init_ptr,
            .vtable = .{
                .deinit = vtable_gen.deinit,
            }
        };

        return obj;
    }

    pub fn deinit(self: *Object, allocator: std.mem.Allocator) void {
        self.vtable.deinit(self.ptr, allocator); 
        allocator.destroy(self);
    }
};

// data must be 8 bytes or lower
pub const Value = struct {
    data: union(enum) {
        number: i64,
        func: usize, // func table index
        object: *Object,
    },
};

test "Value Word Size" {
    std.testing.expect(@sizeOf(Value) <= @sizeOf(*anyopaque));
}
