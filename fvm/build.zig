const std = @import("std");

pub fn build(b: *std.Build) void {
    const rom = "./../roms/2048.fvm";

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build the executable
    const exe = b.addExecutable(.{
        .name = "fvm",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Link with C library
    exe.linkLibC();

    exe.root_module.addAnonymousImport("rom", .{ .root_source_file = b.path(rom) });

    // Install the executable
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
