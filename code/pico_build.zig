const std = @import("std");

const PicoPlatform = enum { RP2040 };

/// Adds a "load" step to the build which will call picotool (must be available in the path)
/// To load the input UF2 to the first found RP2040 in boot mode
/// Then restarts the board.
pub fn addLoadStep(b: *std.Build, uf2_path: []const u8) void {
    const load_uf2_argv = [_][]const u8{ "picotool", "load", uf2_path };
    const load_uf2_cmd = b.addSystemCommand(&load_uf2_argv);
    load_uf2_cmd.setName("picotool Load");
    const restart = [_][]const u8{ "picotool", "reboot" };
    const restart_cmd = b.addSystemCommand(&restart);
    restart_cmd.setName("picotool Restart");
    const load_step = b.step("load", "Loads the uf2 with picotool");
    load_uf2_cmd.step.dependOn(b.getInstallStep());
    restart_cmd.step.dependOn(&load_uf2_cmd.step);
    load_step.dependOn(&restart_cmd.step);
}

/// Gets a Step.Run that will build the .h file out of the input .pio file
/// This must be configured in cmake using the pico_generate_pio_header function
pub fn getPIOBuild(b: *std.Build, project: []const u8, file_name: []const u8) !*std.Build.Step.Run {
    const output = try b.allocator.alloc(u8, file_name.len);
    @memcpy(output, file_name);
    std.mem.replaceScalar(u8, output, '.', '_');
    const target = try std.fmt.allocPrint(b.allocator, "{s}_{s}_h", .{ project, output });
    defer b.allocator.free(target);
    const make_argv = [_][]const u8{ "cmake", "--build", b.install_path, "--target", target, "--parallel" };
    const cmake_build = b.addSystemCommand(&make_argv);
    cmake_build.has_side_effects = true;
    cmake_build.addCheck(.{ .expect_term = .{ .Exited = 0 } });
    cmake_build.setName(target);
    return cmake_build;
}

/// Returns Cmake configuration step
/// This generally should run first - build step dependencies are not established in this code.
pub fn getCmakeConfig(b: *std.Build) *std.Build.Step.Run {
    // There is some nuance around how ZLS does the build so be careful changing any of this
    // I don't really understand it.
    const cmake_argv = [_][]const u8{ "cmake", "-B", b.install_path };
    const cmake_config = b.addSystemCommand(&cmake_argv);
    cmake_config.setName("CmakeConfig");
    cmake_config.has_side_effects = true;
    cmake_config.addCheck(.{ .expect_term = .{ .Exited = 0 } });
    return cmake_config;
}

/// returns Cmake build step (must be run after configuration and after the zig build is done - last)
/// The dependencies are not established in this function.
pub fn getCmakeBuild(b: *std.Build) *std.Build.Step.Run {
    const make_argv = [_][]const u8{ "cmake", "--build", b.install_path, "--parallel" };
    const cmake_build = b.addSystemCommand(&make_argv);
    cmake_build.has_side_effects = true;
    return cmake_build;
}

/// Return resolved target for the input RPxxxx platform
pub fn getTarget(b: *std.Build, platform: PicoPlatform) !std.Build.ResolvedTarget {
    switch (platform) {
        .RP2040 => {
            const targetq = std.zig.CrossTarget{
                .abi = .eabi,
                .cpu_arch = .thumb,
                .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
                .os_tag = .freestanding,
            };
            return b.resolveTargetQuery(targetq);
        },
    }
}

/// Returns TranslateC build step with all of the pico SDK include directories added
/// It also has some defines to work around limitations of the translate (or my ignorance)
/// The root source file should import all headers that are needed for the module.
/// it adds the install path prefix to the include dirs but if there is a subdirectory (or any other directory)
/// they will need to be included manually with the addIncludeDir function
/// Board specific defines should show up with auto_config.h which is imported as needed (thus the cmake config dependency)
/// This will try to correctly set the chip defines (based on my read of the cmake stuff)
pub fn getPicoSdk(b: *std.Build, root_source_file: std.Build.LazyPath, platform: PicoPlatform) !*std.Build.Step.TranslateC {
    // TODO: Not sure how to do this the "right" way.
    // Essentially this is needed so we can find the right headers: <assert.h> & <sys/cdefs.h>.
    // using the "correct" target seems to fail there in the translation of pico_sdk code.
    const targetq = std.zig.CrossTarget{
        .abi = .gnu,
        .cpu_arch = .x86_64,
        .os_tag = .linux,
    };

    const c_translate = b.addTranslateC(.{
        .link_libc = true,
        .optimize = .ReleaseSmall,
        .target = b.resolveTargetQuery(targetq),
        .root_source_file = root_source_file,
    });
    // this should catch generated xxx.pio.h in most cases I think.  If there are subdirs in cmake they will need to be added manually.
    c_translate.addIncludeDir(b.install_path);

    var arena = std.heap.ArenaAllocator.init(b.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const pico_sdk_path = try std.process.getEnvVarOwned(allocator, "PICO_SDK_PATH");

    const temp_path = try std.fs.path.join(allocator, &.{ b.install_path, "generated", "pico_base" });
    c_translate.addIncludeDir(temp_path);

    // Pico SRC folder
    const src_path = try std.fs.path.join(allocator, &.{ pico_sdk_path, "src" });
    var pico_includes = try findIncludeDirs(&arena, src_path, "include");
    for (pico_includes.items) |path| {
        c_translate.addIncludeDir(path);
    }
    defer pico_includes.deinit();

    // TinyUSB src folder
    const tiny_usb_path_src = try std.fs.path.join(allocator, &.{ pico_sdk_path, "lib", "tinyusb", "src" });
    c_translate.addIncludeDir(tiny_usb_path_src);
    var tiny_usb_includes = try findIncludeDirs(&arena, tiny_usb_path_src, "");
    for (tiny_usb_includes.items) |path| {
        c_translate.addIncludeDir(path);
    }
    defer tiny_usb_includes.deinit();
    // TinyUSB hw folder
    const tiny_usb_path_hw = try std.fs.path.join(allocator, &.{ pico_sdk_path, "lib", "tinyusb", "hw" });
    c_translate.addIncludeDir(tiny_usb_path_hw);

    // TODO wireless stuff etc.

    // Works around some issue when translating uart.h
    c_translate.defineCMacroRaw("PICO_DEFAULT_UART_INSTANCE()=uart0");

    // Related to the libc issues above I think; work around by doing this.
    // Pulled from {PICO_SDK_PATH}/src/rp2_common/pico_clib_interface/include/llvm_libc/sys/cdefs.h
    c_translate.defineCMacroRaw("__CONCAT1(x,y)=x ## y");
    c_translate.defineCMacroRaw("__CONCAT(x,y)=__CONCAT1(x,y)");
    c_translate.defineCMacroRaw("__STRING(x)=#x");
    c_translate.defineCMacroRaw("__XSTRING(x)=__STRING(x)");
    c_translate.defineCMacroRaw("__unused=__attribute__((__unused__))");
    c_translate.defineCMacroRaw("__used=__attribute__((__used__))");
    c_translate.defineCMacroRaw("__packed=__attribute__((__packed__))");
    c_translate.defineCMacroRaw("__aligned(x)=__attribute__((__aligned__(x)))");
    c_translate.defineCMacroRaw("__always_inline __inline__ __attribute__((__always_inline__))");
    c_translate.defineCMacroRaw("__noinline=__attribute__((__noinline__))");
    c_translate.defineCMacroRaw("__printflike(fmtarg, firstvararg)=__attribute__((__format__ (__printf__, fmtarg, firstvararg)))");

    // not sure how important these are... see {PICO_SDK_PATH}/src/rp2040.cmake
    switch (platform) {
        .RP2040 => {
            c_translate.defineCMacroRaw("PICO_RP2040=1");
            c_translate.defineCMacroRaw("PICO_RP2350=0");
            c_translate.defineCMacroRaw("PICO_RISCV=0");
            c_translate.defineCMacroRaw("PICO_ARM=1");
            c_translate.defineCMacroRaw("PICO_CMSIS_DEVICE=RP2040");
            // TinyUSB support
            c_translate.defineCMacroRaw("CFG_TUSB_MCU=OPT_MCU_RP2040");
        },
        // TODO others.
    }

    return c_translate;
}

fn findIncludeDirs(arena: *std.heap.ArenaAllocator, root: []const u8, folder_match: []const u8) !std.ArrayList([]const u8) {
    const allocator = arena.allocator();
    var dir_list = std.ArrayList([]const u8).init(allocator);
    var dir = try std.fs.cwd().openDir(root, .{ .no_follow = true, .iterate = true });
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    defer dir.close();
    while (try walker.next()) |entry| {
        if (std.mem.startsWith(u8, entry.basename, folder_match) and entry.kind == .directory) {
            const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, entry.path });
            try dir_list.append(full_path);
        }
    }
    return dir_list;
}
