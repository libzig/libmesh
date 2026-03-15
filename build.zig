const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libself_dep = b.dependency("libself", .{
        .target = target,
        .optimize = optimize,
    });
    const libfast_dep = b.dependency("libfast", .{
        .target = target,
        .optimize = optimize,
    });
    const libself_module = libself_dep.module("libself");
    const libfast_module = libfast_dep.module("libfast");

    // Core library module
    const libmesh_module = b.createModule(.{
        .root_source_file = b.path("lib/libmesh.zig"),
        .target = target,
        .optimize = optimize,
    });
    libmesh_module.addImport("libself", libself_module);
    libmesh_module.addImport("libfast", libfast_module);

    // Export module for downstream users.
    const libmesh_export = b.addModule("libmesh", .{
        .root_source_file = b.path("lib/libmesh.zig"),
        .target = target,
        .optimize = optimize,
    });
    libmesh_export.addImport("libself", libself_module);
    libmesh_export.addImport("libfast", libfast_module);

    // Build static library artifact: libmesh.a
    const lib = b.addLibrary(.{
        .name = "mesh",
        .root_module = libmesh_module,
        .linkage = .static,
    });

    b.installArtifact(lib);

    // Unit tests
    const lib_unit_tests = b.addTest(.{
        .root_module = libmesh_module,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
