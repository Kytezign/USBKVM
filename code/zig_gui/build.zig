const Build = @import("std").Build;

const CFlags = &.{};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "usbkvm_sdl3",
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    exe.linkSystemLibrary("SDL3");
    exe.linkLibC();
    exe.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "." } }); // Look for C source files
    b.installArtifact(exe);

    const run = b.step("run", "Run");
    const run_cmd = b.addRunArtifact(exe);
    run.dependOn(&run_cmd.step);
}
