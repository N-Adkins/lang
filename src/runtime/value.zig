//! Runtime value data, universal tagged union for any variable / constant

const std = @import("std");

// data must be 8 bytes or lower
pub const Value = struct {
    data: union(enum) {
        number: f64,
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
            .number => |number| try writer.print("{d}", .{number}),
            .func => |func| try writer.print("[Function {d}]", .{func}),
            .object => |obj| {
                switch (obj.data) {
                    .string => |str| try writer.print("{s}", .{str.raw}),
                    // else => try writer.print("[Object object]", .{}),
                }
            },
        }
    }

    pub fn dupe(self: *const Value, allocator: std.mem.Allocator) std.mem.Allocator.Error!Value {
        var new = Value{ .data = undefined };

        switch (self.data) {
            .object => |obj| new.data = .{ .object = try obj.dupe(allocator) },
            inline else => |_| {
                new.data = self.data;
            },
        }

        return new;
    }
};

pub const Object = struct {
    next: ?*Object = null, // used for naive GC impl for now
    marked: bool = false, // this too

    data: union(enum) {
        string: String,
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

    pub fn dupe(self: *const Object, allocator: std.mem.Allocator) std.mem.Allocator.Error!*Object {
        const new = try allocator.create(Object);
        errdefer allocator.destroy(new);

        switch (self.data) {
            .string => |str| {
                var str_ref = str;
                new.data.string = try str_ref.dupe(allocator);
            },
        }

        return new;
    }
};

pub const String = struct {
    raw: []const u8,

    pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
        allocator.free(self.raw);
    }

    pub fn dupe(self: *String, allocator: std.mem.Allocator) std.mem.Allocator.Error!String {
        return String{
            .raw = try allocator.dupe(u8, self.raw),
        };
    }
};

test "Value Word Size" {
    try std.testing.expect(@sizeOf(Value) <= @sizeOf(*anyopaque));
}
