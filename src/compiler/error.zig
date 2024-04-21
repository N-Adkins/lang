const std = @import("std");
const lexer = @import("lexer.zig");

pub const ErrorTag = enum(u16) {
    unexpected_character,
    unexpected_token,
    unexpected_end,
    unterminated_string,
    unterminated_block,
    symbol_not_found,
    symbol_shadowing,
    mismatched_types,
    constant_overflow,
    local_overflow,
};

/// Error metadata, contains all information needed to construct
/// an error message except for the source code
pub const Error = struct {
    tag: ErrorTag,
    message: []const u8,
    details: ?struct {
        line: []const u8,
        line_num: usize,
        highlight: usize,
    },

    pub fn deinit(self: *Error, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};

/// Error context that should be passed to all compilation passes, allows
/// error queueing and can form full error messages
pub const ErrorContext = struct {
    source: []const u8,
    errors: std.DoublyLinkedList(Error) = std.DoublyLinkedList(Error){},
    allocator: std.mem.Allocator,
    const Node = std.DoublyLinkedList(Error).Node;

    pub fn deinit(self: *ErrorContext) void {
        while (self.errors.popFirst()) |node| {
            node.data.deinit(self.allocator);
            self.allocator.destroy(node);
        }
    }

    pub fn newError(self: *ErrorContext, tag: ErrorTag, comptime message_fmt: []const u8, args: anytype, index: ?usize) std.mem.Allocator.Error!void {
        const message = std.fmt.allocPrint(self.allocator, message_fmt, args) catch "Allocation Failure";

        const err = blk: {
            if (index) |i| {
                break :blk self.lineError(tag, message, i);
            } else {
                break :blk Error{
                    .tag = tag,
                    .message = message,
                    .details = null,
                };
            }
        };

        const node = try self.allocator.create(Node);
        node.data = err;
        self.errors.append(node);
    }

    pub fn errorFromToken(self: *ErrorContext, tag: ErrorTag, comptime message: []const u8, args: anytype, token: lexer.Token) std.mem.Allocator.Error!void {
        try self.newError(tag, message, args, token.start);
    }

    pub fn printErrors(self: *ErrorContext) void {
        while (self.errors.popFirst()) |node| {
            var err = node.data;
            self.printError(err);
            err.deinit(self.allocator);
            self.allocator.destroy(node);
        }
    }

    pub fn hasErrors(self: *ErrorContext) bool {
        return self.errors.first != null;
    }

    fn printError(self: *ErrorContext, err: Error) void {
        _ = self;
        const stderr = std.io.getStdErr().writer();
        const errcode = @intFromEnum(err.tag);
        if (err.details) |details| {
            stderr.print(
                "[E{d:0>4}]: {s}\nLine {d:0>4}: \"{s}\"\n",
                .{ errcode, err.message, details.line_num, details.line },
            ) catch {};
            stderr.writeByteNTimes(' ', details.highlight + 12) catch {};
            _ = stderr.writeAll("^\n") catch {};
        } else {
            stderr.print(
                "[E{d:0>4}]: {s}\n",
                .{ errcode, err.message },
            ) catch {};
        }
    }

    fn lineError(self: *ErrorContext, tag: ErrorTag, message: []const u8, index: usize) Error {
        const line_data = self.getLine(index);
        const highlight = index - (@intFromPtr(line_data.line.ptr) - @intFromPtr(self.source.ptr));
        return Error{
            .tag = tag,
            .message = message,
            .details = .{
                .line = line_data.line,
                .line_num = line_data.num,
                .highlight = highlight,
            },
        };
    }

    fn getLine(self: *ErrorContext, index: usize) struct { line: []const u8, num: usize } {
        var line_num: usize = 1;
        var start: usize = 0;

        for (0..self.source.len) |i| {
            const byte = self.source[i];
            if (byte == '\n' or i == self.source.len - 1) {
                if (index >= start and index <= i) {
                    const end = if (i == self.source.len - 1) i + 1 else i;
                    return .{ .line = self.source[start .. end - 1], .num = line_num };
                }
                line_num += 1;
                start = i + 1;
            }
        }

        unreachable;
    }
};
