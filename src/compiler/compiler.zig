//! Wrapper over all compiler passes that executes them all

const std = @import("std");
const err = @import("error.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const value = @import("../runtime/value.zig");
const code_pass = @import("passes/codegen.zig");
const symbol_pass = @import("passes/symbol_populate.zig");
const type_pass = @import("passes/type_check.zig");

/// Container for the bytecode and constants that are obtained
/// during the code generation pass
pub const CompileResult = struct {
    bytecode: [][]const u8,
    constants: []const value.Value,

    pub fn deinit(self: *CompileResult, allocator: std.mem.Allocator) void {
        for (self.bytecode) |func| {
            allocator.free(func);
        }
        allocator.free(self.bytecode);
        allocator.free(self.constants);
    }
};

/// Compiles the passed source code into bytecode and related data
pub fn compile(allocator: std.mem.Allocator, source: []const u8) anyerror!CompileResult {
    var err_ctx = err.ErrorContext{
        .source = source,
        .allocator = allocator,
    };
    defer err_ctx.deinit();

    const result = runPasses(allocator, &err_ctx, source) catch |comp_err| {
        if (err_ctx.hasErrors()) {
            err_ctx.printErrors();
        }
        return comp_err;
    };

    return result;
}

/// Wrapper over the compiler passes so that handling errors is simpler in the compile function
fn runPasses(allocator: std.mem.Allocator, err_ctx: *err.ErrorContext, source: []const u8) anyerror!CompileResult {
    var lex = lexer.Lexer.init(allocator, err_ctx, source);
    defer lex.deinit();
    try lex.tokenize();

    var parse = parser.Parser.init(allocator, err_ctx, &lex);
    defer parse.deinit();
    try parse.parse();

    var symbol_populate_pass = try symbol_pass.Pass.init(allocator, err_ctx, &parse.root);
    defer symbol_populate_pass.deinit();
    try symbol_populate_pass.run();

    var type_check_pass = try type_pass.Pass.init(allocator, err_ctx, &parse.root);
    defer type_check_pass.deinit();
    try type_check_pass.run();

    var codegen_pass = try code_pass.Pass.init(allocator, err_ctx, &parse.root);
    defer codegen_pass.deinit();
    try codegen_pass.run();

    const bytecode = try allocator.alloc([]const u8, codegen_pass.bytecode.items.len);
    for (0..codegen_pass.bytecode.items.len) |i| {
        bytecode[i] = try allocator.dupe(u8, codegen_pass.bytecode.items[i].code.items);
    }
    const constants = try allocator.dupe(value.Value, codegen_pass.constants.items);

    return CompileResult{ .bytecode = bytecode, .constants = constants };
}
