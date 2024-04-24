//! Runtime value data, universal tagged union for any variable / constant

const std = @import("std");
const vm = @import("vm.zig");

// data must be 8 bytes or lower
pub const Value = struct {
    data: union(enum) {
        integer: i64,
        boolean: bool,
        func: usize, // func table index
        object: *Object,
    },

    // Only use this for constants, not during runtime.
    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.data) {
            .object => |obj| {
                obj.deinit(allocator);
                allocator.destroy(obj);
            },
            else => {},
        }
    }

    pub fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        switch (self.data) {
            .integer => |int| try writer.print("{d}", .{int}),
            .boolean => |boolean| try writer.print("{}", .{boolean}),
            .func => |func| try writer.print("[Function {d}]", .{func}),
            .object => |obj| {
                switch (obj.data) {
                    .string => |str| try writer.print("{s}", .{str.raw}),
                    .array => |array| {
                        try writer.writeByte('[');
                        for (0..array.items.items.len) |i| {
                            try writer.print("{any}", .{array.items.items[i]});
                            if (i < array.items.items.len - 1) {
                                try writer.writeAll(", ");
                            }
                        }
                        try writer.writeByte(']');
                    },
                    // else => try writer.print("[Object object]", .{}),
                }
            },
        }
    }

    pub inline fn dupe(self: *const Value, allocator: std.mem.Allocator) Value {
        switch (self.data) {
            .object => |obj| return .{ .data = .{ .object = obj.dupe(allocator) } },
            inline else => |_| {
                return self.*;
            },
        }
    }

    /// Assumes both are the same type
    pub fn equals(self: *const Value, rhs: Value) bool {
        switch (self.data) {
            .integer => |int| return int == rhs.data.integer,
            .boolean => |boolean| return boolean == rhs.data.boolean,
            .func => |func| return func == rhs.data.func,
            .object => |obj| return obj.equals(rhs.data.object),
        }
    }
};

pub const Object = struct {
    next: ?*Object = null, // used for naive GC impl for now
    marked: bool = false, // this too

    data: union(enum) {
        string: String,
        array: Array,
    },

    pub fn deinit(self: *Object, allocator: std.mem.Allocator) void {
        switch (self.data) {
            inline else => |*e| {
                if (std.meta.hasMethod(@TypeOf(e), "deinit")) {
                    e.deinit(allocator);
                }
            },
        }
    }

    pub inline fn dupe(self: *const Object, allocator: std.mem.Allocator) *Object {
        const new = allocator.create(Object) catch |err| {
            vm.errorHandle(err);
            unreachable;
        };

        switch (self.data) {
            .string => |str| {
                var str_ref = str;
                new.data = .{ .string = str_ref.dupe(allocator) };
            },
            .array => |array| {
                var array_ref = array;
                new.data = .{ .array = array_ref.dupe(allocator) };
            },
        }

        return new;
    }

    /// Assumes same types
    pub fn equals(self: *const Object, rhs: *const Object) bool {
        switch (self.data) {
            .string => |str| return std.mem.eql(u8, str.raw, rhs.data.string.raw),
            .array => |array| {
                if (array.items.items.len != rhs.data.array.items.items.len) {
                    return false;
                }
                for (0..array.items.items.len) |i| {
                    if (!array.items.items[i].equals(rhs.data.array.items.items[i])) {
                        return false;
                    }
                }
                return true;
            },
        }
    }
};

pub const String = struct {
    raw: []const u8,

    pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
        allocator.free(self.raw);
    }

    pub fn dupe(self: *String, allocator: std.mem.Allocator) String {
        return String{
            .raw = allocator.dupe(u8, self.raw) catch |err| {
                vm.errorHandle(err);
                unreachable;
            },
        };
    }
};

pub const Array = struct {
    items: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},

    pub fn deinit(self: *Array, allocator: std.mem.Allocator) void {
        for (self.items.items) |*item| {
            item.deinit(allocator);
        }
        self.items.deinit(allocator);
    }

    pub fn dupe(self: *Array, allocator: std.mem.Allocator) Array {
        var new_items = std.ArrayListUnmanaged(Value).initCapacity(allocator, self.items.items.len) catch |err| {
            vm.errorHandle(err);
            unreachable;
        };

        for (0..self.items.items.len) |i| {
            new_items.append(allocator, self.items.items[i].dupe(allocator)) catch |err| {
                vm.errorHandle(err);
                unreachable;
            };
        }

        return Array{ .items = new_items };
    }
};

test "Value Word Size" {
    try std.testing.expect(@sizeOf(Value) <= @sizeOf(*anyopaque));
}
