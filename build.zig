const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "elkyn-db",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add dependencies
    exe.linkSystemLibrary("lmdb");
    exe.linkLibC();

    b.installArtifact(exe);

    // Simple server executable (with auth support)
    const simple_server = b.addExecutable(.{
        .name = "elkyn-server",
        .root_source_file = b.path("src/simple_server_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    simple_server.linkSystemLibrary("lmdb");
    simple_server.linkLibC();
    
    b.installArtifact(simple_server);

    // Embedded library (shared library for bindings)
    const embedded_lib = b.addSharedLibrary(.{
        .name = "elkyn-embedded",
        .root_source_file = b.path("src/embedded_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    embedded_lib.linkSystemLibrary("lmdb");
    embedded_lib.linkLibC();
    
    b.installArtifact(embedded_lib);

    // Static library version for direct linking
    const static_lib = b.addStaticLibrary(.{
        .name = "elkyn-embedded-static",
        .root_source_file = b.path("src/embedded_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    static_lib.linkSystemLibrary("lmdb");
    static_lib.linkLibC();
    
    b.installArtifact(static_lib);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test configuration
    const test_step = b.step("test", "Run unit tests");
    
    // Use the all_tests.zig file to run all tests with proper module context
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/all_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    unit_tests.linkSystemLibrary("lmdb");
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    // Test filter option
    const test_filter = b.option([]const u8, "test-filter", "Filter tests by name");
    if (test_filter) |filter| {
        unit_tests.filters = &.{filter};
    }

    // Benchmark step
    const bench_step = b.step("bench", "Run benchmarks");
    
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_source_file = b.path("bench/bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    
    bench_exe.linkSystemLibrary("lmdb");
    bench_exe.linkLibC();
    
    const run_bench = b.addRunArtifact(bench_exe);
    bench_step.dependOn(&run_bench.step);

    // Coverage option
    const coverage = b.option(bool, "test-coverage", "Enable test coverage");
    if (coverage orelse false) {
        // TODO: Add coverage flags when Zig supports it better
    }
}