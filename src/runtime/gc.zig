const std = @import("std");
const Allocator = std.mem.Allocator;

pub const GCAllocator = struct {
    inner: Allocator,

    pub fn init(inner: Allocator) GCAllocator {
        return GCAllocator{
            .inner = inner,
        };
    }

    pub fn allocator(self: *GCAllocator) Allocator {
        return Allocator{
            .ptr = self,
            .vtable = .{
                .alloc = alloc,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *GCAllocator = @ptrCast(@alignCast(ctx));
        return self.allocInner(len, ptr_align, ret_addr) orelse null;
    }
};
