//! Wrapper over all compiler passes that executes them all

const std = @import("std");
const err = @import("error.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const value = @import("../runtime/value.zig");
const code_pass = @import("passes/bytecode_backend.zig");
const symbol_pass = @import("passes/symbol_populate.zig");
const type_pass = @import("passes/type_check.zig");

/// Container for the bytecode and constants that are obtained
/// during the code generation pass
pub const CompileResult = struct {
    bytecode: [][]const u8,
    constants: []value.Value,

    pub fn deinit(self: *CompileResult, allocator: std.mem.Allocator) void {
        for (self.bytecode) |block| {
            allocator.free(block);
        }
        allocator.free(self.bytecode);
        for (self.constants) |constant| {
            switch (constant.data) {
                .object => |obj| {
                    obj.deinit(allocator);
                    allocator.destroy(obj);
                },
                else => {},
            }
        }
        allocator.free(self.constants);
    }
};

/// Compiles the passed source code into bytecode and related data
pub fn compile(allocator: std.mem.Allocator, source: []const u8) anyerror!CompileResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var err_ctx = err.ErrorContext{
        .source = source,
        .allocator = arena_allocator,
    };

    const result = runPasses(arena_allocator, allocator, &err_ctx, source) catch |comp_err| {
        if (err_ctx.hasErrors()) {
            err_ctx.printErrors();
        }
        return comp_err;
    };

    return result;
}

/// Wrapper over the compiler passes so that handling errors is simpler in the compile function
fn runPasses(arena_allocator: std.mem.Allocator, gpa_allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, source: []const u8) anyerror!CompileResult {
    var lex = lexer.Lexer.init(arena_allocator, err_ctx, source);
    try lex.tokenize();

    var parse = parser.Parser.init(arena_allocator, err_ctx, &lex);
    try parse.parse();

    var symbol_populate_pass = try symbol_pass.Pass.init(arena_allocator, err_ctx, &parse.root);
    try symbol_populate_pass.run();

    var type_check_pass = type_pass.Pass.init(arena_allocator, err_ctx, &parse.root);
    try type_check_pass.run();

    var codegen_pass = try code_pass.Pass.init(arena_allocator, err_ctx, &parse.root);
    try codegen_pass.run();

    const bytecode = try gpa_allocator.alloc([]const u8, codegen_pass.bytecode.items.len);
    for (0..codegen_pass.bytecode.items.len) |i| {
        bytecode[i] = try gpa_allocator.dupe(u8, codegen_pass.bytecode.items[i].code.items);
    }
    const constants = try gpa_allocator.alloc(value.Value, codegen_pass.constants.items.len);
    for (0..constants.len) |i| {
        constants[i] = codegen_pass.constants.items[i].dupe(gpa_allocator);
    }

    return CompileResult{ .bytecode = bytecode, .constants = constants };
}
