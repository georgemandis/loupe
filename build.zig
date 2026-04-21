const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const target_os = target.result.os.tag;

    // Shared module for vision core logic
    const vision_mod = b.createModule(.{
        .root_source_file = b.path("src/vision.zig"),
        .target = target,
        .optimize = optimize,
    });

    // When cross-compiling for macOS (e.g. -Dtarget=x86_64-macos on an aarch64
    // host), Zig doesn't auto-discover the SDK paths. Pass -Dmacos-sdk=/path/to/sdk
    // to provide them.
    const is_native = target.query.isNativeOs() and target.query.isNativeCpu();
    if (!is_native and target_os == .macos) {
        const macos_sdk = b.option([]const u8, "macos-sdk", "Path to macOS SDK for cross-compilation");
        if (macos_sdk) |sdk| {
            vision_mod.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/usr/lib", .{sdk}) });
            vision_mod.addFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{sdk}) });
        }
    }

    switch (target_os) {
        .macos => {
            vision_mod.linkSystemLibrary("objc", .{});
            vision_mod.linkFramework("Foundation", .{});
            vision_mod.linkFramework("AppKit", .{});
            vision_mod.linkFramework("Vision", .{});
            vision_mod.linkFramework("CoreGraphics", .{});
            vision_mod.linkFramework("CoreImage", .{});
            vision_mod.linkFramework("ImageIO", .{});
            vision_mod.linkFramework("CoreVideo", .{});
        },
        .windows => {
            vision_mod.linkSystemLibrary("api-ms-win-core-winrt-l1-1-0", .{});
            vision_mod.linkSystemLibrary("api-ms-win-core-winrt-string-l1-1-0", .{});
        },
        else => {
            // No Linux support. build.zig stays silent so `zig build --help` still works.
            // vision.zig @compileError enforces the restriction at compile time.
        },
    }

    // Dynamic library (C ABI for FFI consumers)
    // link_libc required because c_api.zig uses std.heap.c_allocator (malloc/free)
    const lib_dynamic = b.addLibrary(.{
        .name = "loupe",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "vision", .module = vision_mod },
            },
        }),
    });
    b.installArtifact(lib_dynamic);

    // Static library for embedding
    const lib_static = b.addLibrary(.{
        .name = "loupe",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "vision", .module = vision_mod },
            },
        }),
    });
    b.installArtifact(lib_static);

    // CLI executable
    const exe = b.addExecutable(.{
        .name = "loupe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "vision", .module = vision_mod },
            },
        }),
    });
    b.installArtifact(exe);

    // Run step for CLI
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the loupe CLI");
    run_step.dependOn(&run_cmd.step);
}
