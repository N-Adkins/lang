const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "lang",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .use_llvm = false, 
        .use_lld = false,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .use_llvm = false,
        .use_lld = false,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
    
    //const docs = b.addObject(.{
    //  .name = "Lang",
    //  .root_source_file = .{ .path = "src/main.zig" },
    //  .target = target,
    //  .optimize = optimize,
    //});

    //const install_docs = b.addInstallDirectory(.{
    //  .source_dir = docs.getEmittedDocs(),
    //  .install_dir = .prefix,
    //  .install_subdir = "docs",
    //});

    //const docs_step = b.step("docs", "Generate documentation");
    //docs_step.dependOn(&install_docs.step);
}
