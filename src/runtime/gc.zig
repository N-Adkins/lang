const std = @import("std");
const value = @import("value.zig");
const vm = @import("vm.zig");

pub const GC = struct {
    record_list: ?*value.Object = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GC {
        return GC{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GC) void {
        var iter = self.record_list;
        while (iter) |obj| {
            iter = obj.next;
            obj.deinit(self.allocator);
            self.allocator.destroy(obj);
        }
    }

    pub fn newObject(self: *GC) *value.Object {
        const object = self.allocator.create(value.Object) catch |err| {
            vm.errorHandle(err);
            unreachable;
        };
        object.next = self.record_list;
        self.record_list = object;
        return object;
    }

    pub fn linkObject(self: *GC, object: *value.Object) void {
        object.next = self.record_list;
        self.record_list = object;
    }

    pub fn run(self: *GC, stack: []value.Value) void {
        // Mark all referenced objects
        for (stack) |*item| {
            self.markValue(item);
        }

        // Check all objects and delete objects that aren't marked
        var iter = self.record_list;
        var prev: ?*value.Object = null;
        while (iter) |obj| {
            iter = obj.next;
            if (!obj.marked) {
                if (prev) |prev_ptr| {
                    prev_ptr.next = obj.next;
                } else {
                    self.record_list = obj.next;
                }
                // Destroy unmarked objects as they have
                // no references
                obj.deinit(self.allocator);
                self.allocator.destroy(obj);
            } else {
                // Unmark marked objects but leave them
                obj.marked = false;
                prev = obj;
            }
        }
    }

    fn markValue(self: *GC, item: *value.Value) void {
        _ = self;
        switch (item.data) {
            .integer => |_| {},
            .boolean => |_| {},
            .func => |_| {},
            .object => |obj| {
                obj.marked = true;
            },
        }
    }
};
