const std = @import("std");
const Step = std.Build.Step;

pub fn build(b: *std.Build) void {
    const t = b.standardTargetOptions(.{});
    const o = b.standardOptimizeOption(.{});

    const imports = &[_]std.Build.Module.Import{
        .{ .name = "bounded_array", .module = b.dependency("bounded_array", .{ .target = t, .optimize = o }).module("bounded_array") },
    };

    _ = b.addModule("zig_kit", .{ .root_source_file = b.path("src/root.zig"), .target = t, .optimize = o, .imports = imports });

    const test_mod = b.createModule(.{ .root_source_file = b.path("src/tests.zig"), .target = t, .optimize = o, .imports = imports });

    // Add "check" command to quickly check if the project compiles.
    const check: *Step.Compile = b.addTest(.{ .name = "check", .root_module = test_mod });
    b.step("check", "Check if project compiles").dependOn(&check.step);

    // Add "test" command.
    const tests: *Step.Compile = b.addTest(.{ .name = "test", .root_module = test_mod });
    const run_tests: *Step.Run = b.addRunArtifact(tests);
    b.step("test", "Run unit tests").dependOn(&run_tests.step);
}
