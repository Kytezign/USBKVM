const std = @import("std");
const pico = @import("pico_build.zig");
const TranslateC = std.Build.Step.TranslateC;

pub fn build(b: *std.Build) !void {
    // Create sdk module, can be repeated for different headers (also see example header for requirements).
    const host_translate = try pico.getPicoSdk(b, b.path("µhost/host.h"), .RP2040);
    host_translate.addIncludeDir(b.path("µhost").getPath(b));
    host_translate.addIncludeDir(b.path("common").getPath(b));
    var temp_path = try std.fs.path.join(b.allocator, &[_][]const u8{ b.install_path, "µhost" });
    host_translate.addIncludeDir(temp_path);
    b.allocator.free(temp_path);
    const host_sdk = host_translate.createModule();

    // Create sdk module, can be repeated for different headers (also see example header for requirements).
    const guest_translate = try pico.getPicoSdk(b, b.path("µguest/guest_sdk.h"), .RP2040);
    guest_translate.addIncludeDir(b.path("µguest").getPath(b));
    guest_translate.addIncludeDir(b.path("common").getPath(b));
    temp_path = try std.fs.path.join(b.allocator, &[_][]const u8{ b.install_path, "µguest" });

    guest_translate.addIncludeDir(temp_path);
    b.allocator.free(temp_path);

    const guest_sdk = guest_translate.createModule();

    // _______________________________________
    // micro controller builds
    // Host build

    const hostlib = b.addStaticLibrary(.{
        .name = "zhost",
        .root_source_file = b.path("host_main.zig"),
        .target = try pico.getTarget(b, .RP2040),
        .optimize = .Debug,
    });
    hostlib.root_module.addImport("pico_sdk", host_sdk);
    b.installArtifact(hostlib);

    const guestlib = b.addStaticLibrary(.{
        .name = "zguest",
        .root_source_file = b.path("guest_main.zig"),
        .target = try pico.getTarget(b, .RP2040),
        .optimize = .Debug,
    });
    guestlib.root_module.addImport("pico_sdk", guest_sdk);
    b.installArtifact(guestlib);

    // CMAKE --------------------------------------
    // Cmake steps config and build
    // Cmake steps config and build
    const cmake_config = pico.getCmakeConfig(b);
    const cmake_build = pico.getCmakeBuild(b);

    // Try build before to ensure pio headers are generated.
    const h_async = try pico.getPIOBuild(b, "uhost", "async_spi.pio");
    const g_async = try pico.getPIOBuild(b, "uguest", "async_spi.pio");

    var pre_translate = b.step("pretranslate", "Runs cmake commands to enable translation");
    g_async.step.dependOn(&cmake_config.step);
    h_async.step.dependOn(&g_async.step);
    pre_translate.dependOn(&h_async.step);

    // cmake end -----------------------------------------
    // micro con build
    const gui_build_step = b.step("gui", "Builds GUI Binary");

    host_translate.step.dependOn(pre_translate);
    guest_translate.step.dependOn(pre_translate);
    cmake_build.step.dependOn(&hostlib.step);
    cmake_build.step.dependOn(&guestlib.step);
    cmake_build.step.dependOn(gui_build_step);
    b.getInstallStep().dependOn(&cmake_build.step);

    // __________________________________________
    // GUI Build
    for (GUI_TARGETS) |gui_target| {
        const exe = b.addExecutable(.{
            .name = "usbkvm_sdl3",
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "gui_main.zig" } },
            .target = b.resolveTargetQuery(gui_target),
            .optimize = .ReleaseSmall,
        });
        exe.linkLibC();
        exe.linkSystemLibrary2("SDL3", .{ .preferred_link_mode = .dynamic });
        exe.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "guihost" } });

        const gui_install = b.addInstallArtifact(exe, .{});
        gui_build_step.dependOn(&gui_install.step);
    }
}

const GUI_TARGETS = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    // .{ .cpu_arch = .x86_64, .os_tag = .macos },
    // .{ .cpu_arch = .x86_64, .os_tag = .windows },
};
