# Loupe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cross-platform vision CLI & C ABI library in Zig that wraps native OS vision APIs for face detection (with blur/redact), OCR, and barcode/QR scanning.

**Architecture:** Zig library (`vision.zig`) dispatches to platform backends (`platform/macos.zig`). CLI (`main.zig`) provides subcommands (`faces`, `ocr`, `barcode`, `qr`). C ABI layer (`c_api.zig`) exports opaque-handle functions for FFI. Same pattern as whereami and copycat.

**Tech Stack:** Zig 0.14+, macOS Vision framework (`VNDetectFaceRectanglesRequest`, `VNRecognizeTextRequest`, `VNDetectBarcodesRequest`), Core Graphics, Core Image, ImageIO. ObjC runtime via `objc_msgSend`.

**Spec:** `docs/superpowers/specs/2026-04-19-loupe-design.md`

**Reference projects:**
- whereami: `~/Projects/recurse/2026/zig-geocoding/whereami/` — same build.zig pattern, objc.zig, platform dispatch
- copycat: `~/Projects/recurse/2026/clipboard-manager/copycat/` — same pattern + C ABI layer (`src/lib.zig`)

---

## File Structure

```
loupe/
  build.zig               # Build config: exe + dynamic lib + static lib, framework linking
  src/
    main.zig              # CLI: arg parsing, subcommand dispatch, output formatting (human/JSON)
    vision.zig            # Core module: types, platform dispatch (comptime switch on os.tag)
    c_api.zig             # C ABI exports: opaque handles, out-pointers, loupe_free
    objc.zig              # ObjC runtime helpers (copy from copycat/whereami, add any new helpers)
    platform/
      macos.zig           # Vision framework backend: all detection + image I/O + blur/redact
      windows.zig         # Stub: returns error.UnsupportedPlatform for all operations
```

---

### Task 1: Project Scaffold & Build System

**Files:**
- Create: `build.zig`
- Create: `src/main.zig` (minimal, just prints help)
- Create: `src/vision.zig` (types only, no implementation)
- Create: `src/objc.zig` (copy from whereami)
- Create: `src/platform/macos.zig` (stub)
- Create: `src/platform/windows.zig` (stub)

- [ ] **Step 1: Create `build.zig`**

Model after copycat's build.zig. Key differences: link Vision, CoreGraphics, CoreImage, and ImageIO frameworks on macOS. No Linux support.

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const target_os = target.result.os.tag;

    const vision_mod = b.createModule(.{
        .root_source_file = b.path("src/vision.zig"),
        .target = target,
        .optimize = optimize,
    });

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
        },
        .windows => {
            // Stubbed for v1 — no system libraries needed yet
        },
        else => {},
    }

    // Shared library (C ABI)
    const lib = b.addLibrary(.{
        .name = "loupe",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "vision", .module = vision_mod },
            },
        }),
    });
    b.installArtifact(lib);

    // Static library
    const lib_static = b.addLibrary(.{
        .name = "loupe",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
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

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the loupe CLI");
    run_step.dependOn(&run_cmd.step);
}
```

- [ ] **Step 2: Create `src/objc.zig`**

Copy from whereami's `src/objc.zig` (or copycat's — they're identical). This provides `getClass`, `sel`, `msgSend`, `nsString`, `fromNSString`, `nsArrayCount`, `nsArrayObjectAtIndex`, NSData helpers. The file is already proven and stable across both projects.

```bash
cp ~/Projects/recurse/2026/zig-geocoding/whereami/src/objc.zig src/objc.zig
```

Check whether copycat's version has any additional helpers not in whereami's (e.g., `allocateClassPair`, `addMethod`, `registerClassPair`). If so, use copycat's version since it's a superset.

- [ ] **Step 3: Create `src/vision.zig` with types and dispatch stubs**

```zig
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const platform = switch (builtin.os.tag) {
    .macos => @import("platform/macos.zig"),
    .windows => @import("platform/windows.zig"),
    else => @compileError("Unsupported platform. Currently supported: macOS."),
};

pub const BoundingBox = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

pub const FaceResult = struct {
    box: BoundingBox,
    confidence: f64,
};

pub const OcrResult = struct {
    text: []const u8,
    box: BoundingBox,
    confidence: f64,
};

pub const Symbology = enum {
    qr,
    ean13,
    ean8,
    upca,
    upce,
    code128,
    code39,
    code93,
    itf14,
    datamatrix,
    pdf417,
    aztec,
    unknown,
};

pub const BarcodeResult = struct {
    payload: []const u8,
    symbology: Symbology,
    box: BoundingBox,
};

pub const BlurMode = enum {
    blur,
    redact,
};

pub const ImageHandle = platform.ImageHandle;

pub const VisionError = error{
    ImageLoadFailed,
    UnsupportedFormat,
    DetectionFailed,
    SaveFailed,
    UnsupportedPlatform,
    OutOfMemory,
};

// --- Public API (delegates to platform) ---

pub fn loadImage(path: []const u8) VisionError!ImageHandle {
    return platform.loadImage(path);
}

pub fn detectFaces(allocator: Allocator, handle: ImageHandle) VisionError![]FaceResult {
    return platform.detectFaces(allocator, handle);
}

pub fn recognizeText(allocator: Allocator, handle: ImageHandle) VisionError![]OcrResult {
    return platform.recognizeText(allocator, handle);
}

pub fn scanBarcodes(allocator: Allocator, handle: ImageHandle) VisionError![]BarcodeResult {
    return platform.scanBarcodes(allocator, handle);
}

pub fn blurFaces(handle: ImageHandle, faces: []const FaceResult, mode: BlurMode) VisionError!ImageHandle {
    return platform.blurFaces(handle, faces, mode);
}

pub fn saveImage(handle: ImageHandle, path: []const u8) VisionError!void {
    return platform.saveImage(handle, path);
}

pub fn freeImage(handle: ImageHandle) void {
    platform.freeImage(handle);
}

pub fn freeResults(allocator: Allocator, comptime T: type, results: []T) void {
    // Free heap-allocated strings inside results
    for (results) |*r| {
        switch (T) {
            OcrResult => allocator.free(r.text),
            BarcodeResult => allocator.free(r.payload),
            else => {},
        }
    }
    allocator.free(results);
}
```

- [ ] **Step 4: Create `src/platform/macos.zig` stub**

```zig
const std = @import("std");
const vision = @import("../vision.zig");

pub const ImageHandle = *anyopaque; // Will hold CGImageRef

pub fn loadImage(path: []const u8) vision.VisionError!ImageHandle {
    _ = path;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn detectFaces(allocator: std.mem.Allocator, handle: ImageHandle) vision.VisionError![]vision.FaceResult {
    _ = allocator;
    _ = handle;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn recognizeText(allocator: std.mem.Allocator, handle: ImageHandle) vision.VisionError![]vision.OcrResult {
    _ = allocator;
    _ = handle;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn scanBarcodes(allocator: std.mem.Allocator, handle: ImageHandle) vision.VisionError![]vision.BarcodeResult {
    _ = allocator;
    _ = handle;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn blurFaces(handle: ImageHandle, faces: []const vision.FaceResult, mode: vision.BlurMode) vision.VisionError!ImageHandle {
    _ = handle;
    _ = faces;
    _ = mode;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn saveImage(handle: ImageHandle, path: []const u8) vision.VisionError!void {
    _ = handle;
    _ = path;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn freeImage(handle: ImageHandle) void {
    _ = handle;
}
```

- [ ] **Step 5: Create `src/platform/windows.zig` stub**

Same as macos.zig stub but simpler — all functions return `VisionError.UnsupportedPlatform`.

```zig
const std = @import("std");
const vision = @import("../vision.zig");

pub const ImageHandle = *anyopaque;

pub fn loadImage(path: []const u8) vision.VisionError!ImageHandle {
    _ = path;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn detectFaces(allocator: std.mem.Allocator, handle: ImageHandle) vision.VisionError![]vision.FaceResult {
    _ = allocator;
    _ = handle;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn recognizeText(allocator: std.mem.Allocator, handle: ImageHandle) vision.VisionError![]vision.OcrResult {
    _ = allocator;
    _ = handle;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn scanBarcodes(allocator: std.mem.Allocator, handle: ImageHandle) vision.VisionError![]vision.BarcodeResult {
    _ = allocator;
    _ = handle;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn blurFaces(handle: ImageHandle, faces: []const vision.FaceResult, mode: vision.BlurMode) vision.VisionError!ImageHandle {
    _ = handle;
    _ = faces;
    _ = mode;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn saveImage(handle: ImageHandle, path: []const u8) vision.VisionError!void {
    _ = handle;
    _ = path;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn freeImage(handle: ImageHandle) void {
    _ = handle;
}
```

- [ ] **Step 6: Create minimal `src/c_api.zig`**

Just enough to compile. Full implementation in Task 7.

```zig
const vision = @import("vision");
// C ABI exports will be added after core functionality is working.
```

- [ ] **Step 7: Create `src/main.zig` with help output only**

```zig
const std = @import("std");

pub fn main() !void {
    const stdout_file = std.fs.File.stdout();
    var stdout_buf: [4096]u8 = undefined;
    var stdout = stdout_file.writer(&stdout_buf);

    const stderr_file = std.fs.File.stderr();
    var stderr_buf: [4096]u8 = undefined;
    var stderr = stderr_file.writer(&stderr_buf);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage(&stdout.interface);
        try stdout.interface.flush();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printUsage(&stdout.interface);
        try stdout.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "faces") or
        std.mem.eql(u8, command, "ocr") or
        std.mem.eql(u8, command, "barcode") or
        std.mem.eql(u8, command, "qr"))
    {
        try stderr.interface.print("Error: '{s}' not yet implemented\n", .{command});
        try stderr.interface.flush();
        std.process.exit(1);
    }

    try stderr.interface.print("Error: unknown command: {s}\n\n", .{command});
    try printUsage(&stderr.interface);
    try stderr.interface.flush();
    std.process.exit(2);
}

fn printUsage(writer: *std.io.Writer) !void {
    try writer.print(
        \\Usage: loupe <command> <image> [options]
        \\
        \\Commands:
        \\  faces <image>              Detect faces in an image
        \\  ocr <image>                Extract text from an image
        \\  barcode <image>            Detect barcodes in an image
        \\  qr <image>                 Detect QR codes in an image
        \\  help                       Show this help message
        \\
        \\Options:
        \\  -o <output>                Write result image to file (faces only)
        \\  --blur                     Gaussian blur detected faces (requires -o)
        \\  --redact                   Black-box detected faces (requires -o)
        \\  --json                     Output as JSON
        \\  --help, -h                 Show this help message
        \\
        \\Created by George Mandis <george@mand.is>
        \\https://github.com/georgemandis/loupe
        \\
    , .{});
}
```

- [ ] **Step 8: Build and verify**

Run: `cd ~/Projects/recurse/2026/zig-face-recognition/loupe && zig build`
Expected: Compiles without errors.

Run: `zig build run`
Expected: Prints usage help.

Run: `zig build run -- --help`
Expected: Prints usage help.

Run: `zig build run -- faces`
Expected: Prints "not yet implemented" error, exits 1.

- [ ] **Step 9: Commit**

```bash
git add build.zig src/
git commit -m "feat: project scaffold with build system, types, and CLI help"
```

---

### Task 2: Image Loading (macOS)

**Files:**
- Modify: `src/platform/macos.zig` — implement `loadImage`, `freeImage`, `saveImage`

The image loading pipeline on macOS:
1. Convert Zig path string to `CFStringRef` → `CFURLRef`
2. Create `CGImageSourceRef` from URL via `CGImageSourceCreateWithURL`
3. Extract `CGImageRef` via `CGImageSourceCreateImageAtIndex`
4. Return the `CGImageRef` as the opaque `ImageHandle`

For saving:
1. Determine format from file extension (`.jpg`/`.jpeg` → kUTTypeJPEG, `.png` → kUTTypePNG)
2. Convert path to `CFURLRef`
3. Create `CGImageDestinationRef` via `CGImageDestinationCreateWithURL`
4. Add the `CGImageRef` and finalize

- [ ] **Step 1: Implement `loadImage` in `platform/macos.zig`**

Replace the stub `loadImage` with the real implementation. Requires `extern "c"` declarations for:
- `CFStringCreateWithBytes` (create CFString from Zig slice)
- `CFURLCreateWithFileSystemPath` (create CFURL from CFString)
- `CGImageSourceCreateWithURL` (create image source)
- `CGImageSourceCreateImageAtIndex` (extract CGImage)
- `CFRelease` (release CF objects)

```zig
const objc = @import("../objc.zig");
const vision = @import("../vision.zig");

// CoreFoundation externs
extern "c" fn CFRelease(cf: *anyopaque) void;
extern "c" fn CFStringCreateWithBytes(
    alloc: ?*anyopaque,
    bytes: [*]const u8,
    numBytes: i64,
    encoding: u32,
    isExternalRepresentation: bool,
) ?*anyopaque;
extern "c" fn CFURLCreateWithFileSystemPath(
    alloc: ?*anyopaque,
    filePath: *anyopaque,
    pathStyle: i64,
    isDirectory: bool,
) ?*anyopaque;

// ImageIO externs
extern "c" fn CGImageSourceCreateWithURL(url: *anyopaque, options: ?*anyopaque) ?*anyopaque;
extern "c" fn CGImageSourceCreateImageAtIndex(source: *anyopaque, index: usize, options: ?*anyopaque) ?*anyopaque;

// CGImage externs
extern "c" fn CGImageRelease(image: *anyopaque) void;
extern "c" fn CGImageGetWidth(image: *anyopaque) usize;
extern "c" fn CGImageGetHeight(image: *anyopaque) usize;

const kCFStringEncodingUTF8: u32 = 0x08000100;
const kCFURLPOSIXPathStyle: i64 = 0;

pub const ImageHandle = *anyopaque; // CGImageRef

pub fn loadImage(path: []const u8) vision.VisionError!ImageHandle {
    // Path → CFString → CFURL → CGImageSource → CGImage
    const cf_path = CFStringCreateWithBytes(
        null,
        path.ptr,
        @intCast(path.len),
        kCFStringEncodingUTF8,
        false,
    ) orelse return vision.VisionError.ImageLoadFailed;
    defer CFRelease(cf_path);

    const cf_url = CFURLCreateWithFileSystemPath(
        null,
        cf_path,
        kCFURLPOSIXPathStyle,
        false,
    ) orelse return vision.VisionError.ImageLoadFailed;
    defer CFRelease(cf_url);

    const source = CGImageSourceCreateWithURL(cf_url, null) orelse return vision.VisionError.ImageLoadFailed;
    defer CFRelease(source);

    const image = CGImageSourceCreateImageAtIndex(source, 0, null) orelse return vision.VisionError.ImageLoadFailed;
    return image;
}

pub fn freeImage(handle: ImageHandle) void {
    CGImageRelease(handle);
}
```

- [ ] **Step 2: Implement `saveImage` in `platform/macos.zig`**

```zig
// Additional ImageIO externs for saving
extern "c" fn CGImageDestinationCreateWithURL(
    url: *anyopaque,
    image_type: *anyopaque, // CFStringRef (UTI)
    count: usize,
    options: ?*anyopaque,
) ?*anyopaque;
extern "c" fn CGImageDestinationAddImage(
    dest: *anyopaque,
    image: *anyopaque,
    properties: ?*anyopaque,
) void;
extern "c" fn CGImageDestinationFinalize(dest: *anyopaque) bool;

pub fn saveImage(handle: ImageHandle, path: []const u8) vision.VisionError!void {
    const cf_path = CFStringCreateWithBytes(
        null,
        path.ptr,
        @intCast(path.len),
        kCFStringEncodingUTF8,
        false,
    ) orelse return vision.VisionError.SaveFailed;
    defer CFRelease(cf_path);

    const cf_url = CFURLCreateWithFileSystemPath(
        null,
        cf_path,
        kCFURLPOSIXPathStyle,
        false,
    ) orelse return vision.VisionError.SaveFailed;
    defer CFRelease(cf_url);

    // Determine UTI from file extension
    const uti = inferUTI(path) orelse return vision.VisionError.UnsupportedFormat;

    const dest = CGImageDestinationCreateWithURL(cf_url, uti, 1, null) orelse return vision.VisionError.SaveFailed;
    defer CFRelease(dest);

    CGImageDestinationAddImage(dest, handle, null);
    if (!CGImageDestinationFinalize(dest)) {
        return vision.VisionError.SaveFailed;
    }
}

fn inferUTI(path: []const u8) ?*anyopaque {
    // Find the extension
    const dot_pos = std.mem.lastIndexOfScalar(u8, path, '.') orelse return null;
    const ext = path[dot_pos + 1 ..];

    // Return the appropriate UTI CFString constant
    // These are compile-time constant CFStringRefs from ImageIO
    if (std.mem.eql(u8, ext, "png")) {
        return @constCast(@ptrCast(objc.nsString("public.png")));
    } else if (std.mem.eql(u8, ext, "jpg") or std.mem.eql(u8, ext, "jpeg")) {
        return @constCast(@ptrCast(objc.nsString("public.jpeg")));
    }
    return null;
}
```

- [ ] **Step 3: Test image loading manually**

Add a temporary test in main.zig or use `zig build run`:

Run: `zig build run -- faces /path/to/some/test/image.jpg`

At this point `faces` is still "not implemented" but the build should succeed with the new image I/O code compiled in.

- [ ] **Step 4: Commit**

```bash
git add src/platform/macos.zig
git commit -m "feat: macOS image loading and saving via ImageIO/CoreGraphics"
```

---

### Task 3: Face Detection (macOS)

**Files:**
- Modify: `src/platform/macos.zig` — implement `detectFaces`
- Modify: `src/main.zig` — wire up `faces` subcommand

Face detection uses `VNDetectFaceRectanglesRequest` + `VNImageRequestHandler`. The Vision framework is Objective-C, so all calls go through `objc_msgSend`.

The flow:
1. Create `VNImageRequestHandler` from the `CGImageRef`
2. Create `VNDetectFaceRectanglesRequest`
3. Call `performRequests:error:` on the handler
4. Read `results` from the request — array of `VNFaceObservation`
5. Each observation has a `boundingBox` (CGRect in normalized coords, bottom-left origin)
6. Flip Y to top-left origin: `y_flipped = 1.0 - y - height`
7. Read `confidence` from each observation

- [ ] **Step 1: Implement `detectFaces` in `platform/macos.zig`**

Key ObjC calls:
```
handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}]
request = [[VNDetectFaceRectanglesRequest alloc] init]
[handler performRequests:@[request] error:&err]
results = [request results]  // NSArray of VNFaceObservation
for each observation:
    bbox = [observation boundingBox]  // CGRect {origin.x, origin.y, size.width, size.height}
    confidence = [observation confidence]
```

The `boundingBox` is a `CGRect` (4 x f64 = 32 bytes). On ARM64 this is returned in registers (x0-x3), so `objc_msgSend` works directly. If x86_64 support is needed, `objc_msgSend_stret` would be required for structs > 16 bytes.

```zig
const CGRect = extern struct {
    origin_x: f64,
    origin_y: f64,
    size_width: f64,
    size_height: f64,
};

// For CGRect return: on ARM64 objc_msgSend works; on x86_64 need stret
extern "objc" fn objc_msgSend_stret() void;

fn msgSendStret(comptime ReturnType: type, target: anytype, selector: objc.SEL) ReturnType {
    // On ARM64, large structs are still returned via objc_msgSend (hidden sret pointer).
    // On x86_64, structs > 16 bytes use objc_msgSend_stret.
    if (comptime @import("builtin").cpu.arch == .x86_64) {
        const func: *const fn (*ReturnType, objc.id, objc.SEL) callconv(.c) void = @ptrCast(&objc_msgSend_stret);
        var result: ReturnType = undefined;
        func(&result, @ptrCast(target), selector);
        return result;
    } else {
        const func: *const fn (objc.id, objc.SEL) callconv(.c) ReturnType = @ptrCast(&objc.objc_msgSend_raw);
        return func(@ptrCast(target), selector);
    }
}

pub fn detectFaces(allocator: std.mem.Allocator, handle: ImageHandle) vision.VisionError![]vision.FaceResult {
    // Create empty NSDictionary for options
    const NSDictionary = objc.getClass("NSDictionary") orelse return vision.VisionError.DetectionFailed;
    const empty_dict = objc.msgSend(objc.id, NSDictionary, objc.sel("dictionary"), .{});

    // Create VNImageRequestHandler from CGImage
    const VNImageRequestHandler = objc.getClass("VNImageRequestHandler") orelse return vision.VisionError.DetectionFailed;
    const handler_alloc = objc.msgSend(objc.id, VNImageRequestHandler, objc.sel("alloc"), .{});
    const handler = objc.msgSend(objc.id, handler_alloc, objc.sel("initWithCGImage:options:"), .{ handle, empty_dict });

    // Create VNDetectFaceRectanglesRequest
    const VNDetectFaceRectanglesRequest = objc.getClass("VNDetectFaceRectanglesRequest") orelse return vision.VisionError.DetectionFailed;
    const request_alloc = objc.msgSend(objc.id, VNDetectFaceRectanglesRequest, objc.sel("alloc"), .{});
    const request = objc.msgSend(objc.id, request_alloc, objc.sel("init"), .{});

    // Create NSArray with the single request
    const NSArray = objc.getClass("NSArray") orelse return vision.VisionError.DetectionFailed;
    const requests_array = objc.msgSend(objc.id, NSArray, objc.sel("arrayWithObject:"), .{request});

    // Perform the request
    var err_ptr: ?objc.id = null;
    const success = objc.msgSend(bool, handler, objc.sel("performRequests:error:"), .{ requests_array, &err_ptr });
    if (!success) return vision.VisionError.DetectionFailed;

    // Get results
    const results = objc.msgSend(?objc.id, request, objc.sel("results"), .{}) orelse return allocator.alloc(vision.FaceResult, 0) catch return vision.VisionError.OutOfMemory;
    const count = objc.nsArrayCount(results);

    if (count == 0) {
        return allocator.alloc(vision.FaceResult, 0) catch return vision.VisionError.OutOfMemory;
    }

    var faces = allocator.alloc(vision.FaceResult, count) catch return vision.VisionError.OutOfMemory;

    for (0..count) |i| {
        const observation = objc.nsArrayObjectAtIndex(results, i);

        // boundingBox returns CGRect (normalized, bottom-left origin)
        const bbox = msgSendStret(CGRect, observation, objc.sel("boundingBox"));
        const confidence = objc.msgSend(f32, observation, objc.sel("confidence"), .{});

        // Flip Y from bottom-left to top-left origin
        faces[i] = .{
            .box = .{
                .x = bbox.origin_x,
                .y = 1.0 - bbox.origin_y - bbox.size_height,
                .width = bbox.size_width,
                .height = bbox.size_height,
            },
            .confidence = @floatCast(confidence),
        };
    }

    return faces;
}
```

Note: The exact `objc_msgSend` / `objc_msgSend_stret` approach for `CGRect` return values may need adjustment during implementation. Test on the actual machine. ARM64 returns structs up to 4 registers (32 bytes) via normal `objc_msgSend`. CGRect is exactly 32 bytes, so it should work.

- [ ] **Step 2: Wire up `faces` subcommand in `main.zig`**

Replace the "not implemented" branch for `faces` with actual logic:

```zig
if (std.mem.eql(u8, command, "faces")) {
    // Parse remaining args for: <image>, --json, -o <output>, --blur, --redact
    var image_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var json_output = false;
    var blur_mode: ?vision.BlurMode = null;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= args.len) {
                try stderr.interface.print("Error: -o requires a file path\n", .{});
                try stderr.interface.flush();
                std.process.exit(2);
            }
            output_path = args[i];
        } else if (std.mem.eql(u8, arg, "--blur")) {
            blur_mode = .blur;
        } else if (std.mem.eql(u8, arg, "--redact")) {
            blur_mode = .redact;
        } else if (arg[0] != '-' and image_path == null) {
            image_path = arg;
        } else {
            try stderr.interface.print("Error: unknown flag: {s}\n", .{arg});
            try stderr.interface.flush();
            std.process.exit(2);
        }
    }

    const path = image_path orelse {
        try stderr.interface.print("Error: faces requires an image path\n", .{});
        try stderr.interface.flush();
        std.process.exit(2);
    };

    if (blur_mode != null and output_path == null) {
        try stderr.interface.print("Error: --blur/--redact requires -o <output>\n", .{});
        try stderr.interface.flush();
        std.process.exit(2);
    }

    const handle = vision.loadImage(path) catch |err| {
        handleError(err, json_output, &stdout.interface, &stderr.interface);
        unreachable;
    };
    defer vision.freeImage(handle);

    const faces = vision.detectFaces(allocator, handle) catch |err| {
        handleError(err, json_output, &stdout.interface, &stderr.interface);
        unreachable;
    };
    defer allocator.free(faces);

    // Print results
    if (json_output) {
        try printFacesJson(&stdout.interface, faces);
    } else {
        try printFacesHuman(&stdout.interface, faces);
    }

    // Blur/redact and save if requested
    if (blur_mode) |mode| {
        const blurred = vision.blurFaces(handle, faces, mode) catch |err| {
            handleError(err, json_output, &stdout.interface, &stderr.interface);
            unreachable;
        };
        defer vision.freeImage(blurred);
        vision.saveImage(blurred, output_path.?) catch |err| {
            handleError(err, json_output, &stdout.interface, &stderr.interface);
            unreachable;
        };
    }

    try stdout.interface.flush();
    return;
}
```

Also add the helper functions `printFacesHuman`, `printFacesJson`, and `handleError`:

```zig
fn printFacesHuman(writer: *std.io.Writer, faces: []const vision.FaceResult) !void {
    if (faces.len == 0) {
        try writer.print("No faces detected.\n", .{});
        return;
    }
    try writer.print("Found {d} face{s}:\n", .{ faces.len, if (faces.len == 1) "" else "s" });
    for (faces, 1..) |face, i| {
        try writer.print("  Face {d}: ({d:.2}, {d:.2}) {d:.2}x{d:.2} [confidence: {d:.2}]\n", .{
            i, face.box.x, face.box.y, face.box.width, face.box.height, face.confidence,
        });
    }
}

fn printFacesJson(writer: *std.io.Writer, faces: []const vision.FaceResult) !void {
    try writer.print("{{\"faces\":[", .{});
    for (faces, 0..) |face, i| {
        if (i > 0) try writer.print(",", .{});
        try writer.print("{{\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d},\"confidence\":{d}}}", .{
            face.box.x, face.box.y, face.box.width, face.box.height, face.confidence,
        });
    }
    try writer.print("]}}\n", .{});
}

fn handleError(
    err: anyerror,
    json_mode: bool,
    stdout_writer: *std.io.Writer,
    stderr_writer: *std.io.Writer,
) void {
    if (json_mode) {
        const error_key: []const u8 = switch (err) {
            error.ImageLoadFailed => "image_load_failed",
            error.UnsupportedFormat => "unsupported_format",
            error.DetectionFailed => "detection_failed",
            error.SaveFailed => "save_failed",
            error.UnsupportedPlatform => "unsupported_platform",
            else => "unknown_error",
        };
        stdout_writer.print("{{\"error\":\"{s}\"}}\n", .{error_key}) catch {};
        stdout_writer.flush() catch {};
    }

    switch (err) {
        error.ImageLoadFailed => stderr_writer.print("Error: failed to load image.\n", .{}) catch {},
        error.UnsupportedFormat => stderr_writer.print("Error: unsupported image format.\n", .{}) catch {},
        error.DetectionFailed => stderr_writer.print("Error: detection failed.\n", .{}) catch {},
        error.SaveFailed => stderr_writer.print("Error: failed to save image.\n", .{}) catch {},
        error.UnsupportedPlatform => stderr_writer.print("Error: not supported on this platform.\n", .{}) catch {},
        else => stderr_writer.print("Error: unexpected error ({s})\n", .{@errorName(err)}) catch {},
    }
    stderr_writer.flush() catch {};
    std.process.exit(1);
}
```

- [ ] **Step 3: Test face detection**

Find or create a test image with faces. Test:

Run: `zig build run -- faces /path/to/photo-with-faces.jpg`
Expected: Prints "Found N faces:" with bounding boxes.

Run: `zig build run -- faces /path/to/photo-with-faces.jpg --json`
Expected: JSON output with faces array.

Run: `zig build run -- faces /path/to/no-faces.jpg`
Expected: "No faces detected."

Run: `zig build run -- faces nonexistent.jpg`
Expected: "Error: failed to load image." exit code 1.

Run: `zig build run -- faces photo.jpg --blur`
Expected: "Error: --blur/--redact requires -o <output>" exit code 2.

- [ ] **Step 4: Commit**

```bash
git add src/platform/macos.zig src/main.zig
git commit -m "feat: face detection via macOS Vision framework"
```

---

### Task 4: Face Blur & Redact (macOS)

**Files:**
- Modify: `src/platform/macos.zig` — implement `blurFaces`

Two modes:
- **blur**: Create a CGContext, draw the original image, then for each face region apply a Gaussian blur via CIFilter
- **redact**: Create a CGContext, draw the original image, then fill each face region with black rectangles

The implementation approach:
1. Get image dimensions from `CGImageGetWidth`/`CGImageGetHeight`
2. Create a `CGBitmapContext` the same size
3. Draw the original image into it
4. For each face:
   - Convert normalized coords to pixel coords
   - **blur**: Crop the face region, create CIImage, apply CIGaussianBlur filter, render back
   - **redact**: `CGContextSetRGBFillColor(0,0,0,1)` + `CGContextFillRect` on the face region
5. Create a new `CGImage` from the context

- [ ] **Step 1: Implement `blurFaces` with redact mode**

Start with redact (simpler — just fill rectangles):

```zig
// CoreGraphics context externs
extern "c" fn CGBitmapContextCreate(
    data: ?*anyopaque,
    width: usize,
    height: usize,
    bitsPerComponent: usize,
    bytesPerRow: usize,
    space: *anyopaque,
    bitmapInfo: u32,
) ?*anyopaque;
extern "c" fn CGBitmapContextCreateImage(context: *anyopaque) ?*anyopaque;
extern "c" fn CGContextDrawImage(context: *anyopaque, rect: CGRect, image: *anyopaque) void;
extern "c" fn CGContextSetRGBFillColor(context: *anyopaque, r: f64, g: f64, b: f64, a: f64) void;
extern "c" fn CGContextFillRect(context: *anyopaque, rect: CGRect) void;
extern "c" fn CGColorSpaceCreateDeviceRGB() *anyopaque;
extern "c" fn CGColorSpaceRelease(space: *anyopaque) void;

const kCGImageAlphaPremultipliedLast: u32 = 1;

pub fn blurFaces(handle: ImageHandle, faces: []const vision.FaceResult, mode: vision.BlurMode) vision.VisionError!ImageHandle {
    const width = CGImageGetWidth(handle);
    const height = CGImageGetHeight(handle);
    const fw: f64 = @floatFromInt(width);
    const fh: f64 = @floatFromInt(height);

    const color_space = CGColorSpaceCreateDeviceRGB();
    defer CGColorSpaceRelease(color_space);

    const ctx = CGBitmapContextCreate(
        null,
        width,
        height,
        8,
        width * 4,
        color_space,
        kCGImageAlphaPremultipliedLast,
    ) orelse return vision.VisionError.DetectionFailed;

    // Draw original image (CoreGraphics uses bottom-left origin)
    const full_rect = CGRect{ .origin_x = 0, .origin_y = 0, .size_width = fw, .size_height = fh };
    CGContextDrawImage(ctx, full_rect, handle);

    switch (mode) {
        .redact => {
            CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
            for (faces) |face| {
                // Convert normalized top-left coords to CG bottom-left pixel coords
                const px = face.box.x * fw;
                const pw = face.box.width * fw;
                const ph = face.box.height * fh;
                const py = (1.0 - face.box.y - face.box.height) * fh; // flip back to bottom-left
                const face_rect = CGRect{
                    .origin_x = px,
                    .origin_y = py,
                    .size_width = pw,
                    .size_height = ph,
                };
                CGContextFillRect(ctx, face_rect);
            }
        },
        .blur => {
            // Blur implementation — see Step 2
            // For now, fall through to redact as placeholder
            CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
            for (faces) |face| {
                const px = face.box.x * fw;
                const pw = face.box.width * fw;
                const ph = face.box.height * fh;
                const py = (1.0 - face.box.y - face.box.height) * fh;
                const face_rect = CGRect{
                    .origin_x = px,
                    .origin_y = py,
                    .size_width = pw,
                    .size_height = ph,
                };
                CGContextFillRect(ctx, face_rect);
            }
        },
    }

    const result_image = CGBitmapContextCreateImage(ctx) orelse return vision.VisionError.DetectionFailed;
    CFRelease(ctx);
    return result_image;
}
```

- [ ] **Step 2: Implement Gaussian blur mode**

Replace the blur placeholder with CIFilter-based Gaussian blur. For each face region:
1. Crop the face from the CGImage (`CGImageCreateWithImageInRect`)
2. Create a CIImage from the crop
3. Apply CIGaussianBlur filter
4. Render the blurred result back into the CGContext

```zig
// Additional externs for blur
extern "c" fn CGImageCreateWithImageInRect(image: *anyopaque, rect: CGRect) ?*anyopaque;
extern "c" fn CGContextSaveGState(ctx: *anyopaque) void;
extern "c" fn CGContextRestoreGState(ctx: *anyopaque) void;
extern "c" fn CGContextClipToRect(ctx: *anyopaque, rect: CGRect) void;

// Blur via CIFilter uses ObjC:
// CIImage *ciInput = [CIImage imageWithCGImage:croppedCGImage];
// CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
// [blur setValue:ciInput forKey:kCIInputImageKey];
// [blur setValue:@(20.0) forKey:kCIInputRadiusKey];
// CIImage *ciOutput = [blur outputImage];
// CIContext *ciCtx = [CIContext context];
// CGImageRef blurredCG = [ciCtx createCGImage:ciOutput fromRect:[ciInput extent]];
```

The implementer should use `objc.msgSend` for all these calls, following the pattern from the face detection code. Draw the blurred CGImage back into the face region of the context.

- [ ] **Step 3: Test face blur/redact**

Run: `zig build run -- faces photo.jpg -o redacted.jpg --redact`
Expected: Creates `redacted.jpg` with black boxes over faces. Also prints face count to stdout.

Run: `zig build run -- faces photo.jpg -o blurred.png --blur`
Expected: Creates `blurred.png` with Gaussian blur over faces.

Run: `zig build run -- faces no-faces.jpg -o out.jpg --redact`
Expected: Creates `out.jpg` identical to input (no faces to redact). Prints "No faces detected."

- [ ] **Step 4: Commit**

```bash
git add src/platform/macos.zig
git commit -m "feat: face blur and redact via CoreGraphics/CoreImage"
```

---

### Task 5: OCR Text Recognition (macOS)

**Files:**
- Modify: `src/platform/macos.zig` — implement `recognizeText`
- Modify: `src/main.zig` — wire up `ocr` subcommand

OCR uses `VNRecognizeTextRequest`. Same handler pattern as face detection:
1. Create `VNImageRequestHandler` from `CGImageRef`
2. Create `VNRecognizeTextRequest`
3. Set recognition level to accurate: `[request setRecognitionLevel:1]` (VNRequestTextRecognitionLevelAccurate)
4. Perform the request
5. Results are `VNRecognizedTextObservation` objects, each with `topCandidates:` → `VNRecognizedText` → `string` property

- [ ] **Step 1: Implement `recognizeText` in `platform/macos.zig`**

```zig
pub fn recognizeText(allocator: std.mem.Allocator, handle: ImageHandle) vision.VisionError![]vision.OcrResult {
    const NSDictionary = objc.getClass("NSDictionary") orelse return vision.VisionError.DetectionFailed;
    const empty_dict = objc.msgSend(objc.id, NSDictionary, objc.sel("dictionary"), .{});

    const VNImageRequestHandler = objc.getClass("VNImageRequestHandler") orelse return vision.VisionError.DetectionFailed;
    const handler_alloc = objc.msgSend(objc.id, VNImageRequestHandler, objc.sel("alloc"), .{});
    const handler = objc.msgSend(objc.id, handler_alloc, objc.sel("initWithCGImage:options:"), .{ handle, empty_dict });

    const VNRecognizeTextRequest = objc.getClass("VNRecognizeTextRequest") orelse return vision.VisionError.DetectionFailed;
    const request_alloc = objc.msgSend(objc.id, VNRecognizeTextRequest, objc.sel("alloc"), .{});
    const request = objc.msgSend(objc.id, request_alloc, objc.sel("init"), .{});

    // Set recognition level to Accurate (1). Fast = 0.
    objc.msgSend(void, request, objc.sel("setRecognitionLevel:"), .{@as(i64, 1)});

    const NSArray = objc.getClass("NSArray") orelse return vision.VisionError.DetectionFailed;
    const requests_array = objc.msgSend(objc.id, NSArray, objc.sel("arrayWithObject:"), .{request});

    var err_ptr: ?objc.id = null;
    const success = objc.msgSend(bool, handler, objc.sel("performRequests:error:"), .{ requests_array, &err_ptr });
    if (!success) return vision.VisionError.DetectionFailed;

    const results = objc.msgSend(?objc.id, request, objc.sel("results"), .{}) orelse {
        return allocator.alloc(vision.OcrResult, 0) catch return vision.VisionError.OutOfMemory;
    };
    const count = objc.nsArrayCount(results);

    if (count == 0) {
        return allocator.alloc(vision.OcrResult, 0) catch return vision.VisionError.OutOfMemory;
    }

    var ocr_results = allocator.alloc(vision.OcrResult, count) catch return vision.VisionError.OutOfMemory;
    var actual_count: usize = 0;

    for (0..count) |i| {
        const observation = objc.nsArrayObjectAtIndex(results, i);

        // Get top candidate text: [[observation topCandidates:1] firstObject]
        const candidates = objc.msgSend(objc.id, observation, objc.sel("topCandidates:"), .{@as(objc.NSUInteger, 1)});
        const candidate_count = objc.nsArrayCount(candidates);
        if (candidate_count == 0) continue;

        const candidate = objc.nsArrayObjectAtIndex(candidates, 0);
        const nsstr = objc.msgSend(?objc.id, candidate, objc.sel("string"), .{}) orelse continue;
        const cstr = objc.fromNSString(nsstr) orelse continue;
        const len = std.mem.len(cstr);

        const text_copy = allocator.alloc(u8, len) catch return vision.VisionError.OutOfMemory;
        @memcpy(text_copy, cstr[0..len]);

        // Bounding box (normalized, bottom-left origin → flip to top-left)
        const bbox = msgSendStret(CGRect, observation, objc.sel("boundingBox"));
        const confidence = objc.msgSend(f32, candidate, objc.sel("confidence"), .{});

        ocr_results[actual_count] = .{
            .text = text_copy,
            .box = .{
                .x = bbox.origin_x,
                .y = 1.0 - bbox.origin_y - bbox.size_height,
                .width = bbox.size_width,
                .height = bbox.size_height,
            },
            .confidence = @floatCast(confidence),
        };
        actual_count += 1;
    }

    // Shrink to actual size if some observations had no candidates
    if (actual_count < count) {
        return allocator.realloc(ocr_results, actual_count) catch return ocr_results[0..actual_count];
    }
    return ocr_results;
}
```

- [ ] **Step 2: Wire up `ocr` subcommand in `main.zig`**

```zig
if (std.mem.eql(u8, command, "ocr")) {
    var image_path: ?[]const u8 = null;
    var json_output = false;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (arg[0] != '-' and image_path == null) {
            image_path = arg;
        } else {
            try stderr.interface.print("Error: unknown flag: {s}\n", .{arg});
            try stderr.interface.flush();
            std.process.exit(2);
        }
    }

    const path = image_path orelse {
        try stderr.interface.print("Error: ocr requires an image path\n", .{});
        try stderr.interface.flush();
        std.process.exit(2);
    };

    const handle = vision.loadImage(path) catch |err| {
        handleError(err, json_output, &stdout.interface, &stderr.interface);
        unreachable;
    };
    defer vision.freeImage(handle);

    const results = vision.recognizeText(allocator, handle) catch |err| {
        handleError(err, json_output, &stdout.interface, &stderr.interface);
        unreachable;
    };
    defer vision.freeResults(allocator, vision.OcrResult, results);

    if (json_output) {
        try printOcrJson(&stdout.interface, results);
    } else {
        try printOcrHuman(&stdout.interface, results);
    }

    try stdout.interface.flush();
    return;
}
```

Add output formatters:

```zig
fn printOcrHuman(writer: *std.io.Writer, results: []const vision.OcrResult) !void {
    if (results.len == 0) {
        try writer.print("No text detected.\n", .{});
        return;
    }
    for (results) |r| {
        try writer.print("{s}\n", .{r.text});
    }
}

fn printOcrJson(writer: *std.io.Writer, results: []const vision.OcrResult) !void {
    try writer.print("{{\"text\":\"", .{});
    // Combined text
    for (results, 0..) |r, i| {
        if (i > 0) try writer.print("\\n", .{});
        try writeJsonString(writer, r.text);
    }
    try writer.print("\",\"regions\":[", .{});
    for (results, 0..) |r, i| {
        if (i > 0) try writer.print(",", .{});
        try writer.print("{{\"text\":\"", .{});
        try writeJsonString(writer, r.text);
        try writer.print("\",\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d},\"confidence\":{d}}}", .{
            r.box.x, r.box.y, r.box.width, r.box.height, r.confidence,
        });
    }
    try writer.print("]}}\n", .{});
}
```

Also add the `writeJsonString` helper (same pattern as whereami/copycat):

```zig
fn writeJsonString(writer: *std.io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.print("\\\"", .{}),
            '\\' => try writer.print("\\\\", .{}),
            '\n' => try writer.print("\\n", .{}),
            '\r' => try writer.print("\\r", .{}),
            '\t' => try writer.print("\\t", .{}),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => try writer.print("\\u{X:0>4}", .{c}),
            else => try writer.print("{c}", .{c}),
        }
    }
}
```

- [ ] **Step 3: Test OCR**

Run: `zig build run -- ocr /path/to/screenshot-with-text.png`
Expected: Prints extracted text lines.

Run: `zig build run -- ocr /path/to/screenshot-with-text.png --json`
Expected: JSON with text and regions array.

Run: `zig build run -- ocr /path/to/photo-no-text.jpg`
Expected: "No text detected."

- [ ] **Step 4: Commit**

```bash
git add src/platform/macos.zig src/main.zig
git commit -m "feat: OCR text recognition via macOS VNRecognizeTextRequest"
```

---

### Task 6: Barcode & QR Code Scanning (macOS)

**Files:**
- Modify: `src/platform/macos.zig` — implement `scanBarcodes`
- Modify: `src/main.zig` — wire up `barcode` and `qr` subcommands

Barcode detection uses `VNDetectBarcodesRequest`. Results are `VNBarcodeObservation` objects with:
- `payloadStringValue` — the decoded content
- `symbology` — NSString like "VNBarcodeSymbologyQR", "VNBarcodeSymbologyEAN13", etc.
- `boundingBox` — CGRect (normalized)

- [ ] **Step 1: Implement `scanBarcodes` in `platform/macos.zig`**

```zig
pub fn scanBarcodes(allocator: std.mem.Allocator, handle: ImageHandle) vision.VisionError![]vision.BarcodeResult {
    const NSDictionary = objc.getClass("NSDictionary") orelse return vision.VisionError.DetectionFailed;
    const empty_dict = objc.msgSend(objc.id, NSDictionary, objc.sel("dictionary"), .{});

    const VNImageRequestHandler = objc.getClass("VNImageRequestHandler") orelse return vision.VisionError.DetectionFailed;
    const handler_alloc = objc.msgSend(objc.id, VNImageRequestHandler, objc.sel("alloc"), .{});
    const handler = objc.msgSend(objc.id, handler_alloc, objc.sel("initWithCGImage:options:"), .{ handle, empty_dict });

    const VNDetectBarcodesRequest = objc.getClass("VNDetectBarcodesRequest") orelse return vision.VisionError.DetectionFailed;
    const request_alloc = objc.msgSend(objc.id, VNDetectBarcodesRequest, objc.sel("alloc"), .{});
    const request = objc.msgSend(objc.id, request_alloc, objc.sel("init"), .{});

    const NSArray = objc.getClass("NSArray") orelse return vision.VisionError.DetectionFailed;
    const requests_array = objc.msgSend(objc.id, NSArray, objc.sel("arrayWithObject:"), .{request});

    var err_ptr: ?objc.id = null;
    const success = objc.msgSend(bool, handler, objc.sel("performRequests:error:"), .{ requests_array, &err_ptr });
    if (!success) return vision.VisionError.DetectionFailed;

    const results = objc.msgSend(?objc.id, request, objc.sel("results"), .{}) orelse {
        return allocator.alloc(vision.BarcodeResult, 0) catch return vision.VisionError.OutOfMemory;
    };
    const count = objc.nsArrayCount(results);

    if (count == 0) {
        return allocator.alloc(vision.BarcodeResult, 0) catch return vision.VisionError.OutOfMemory;
    }

    var barcodes = allocator.alloc(vision.BarcodeResult, count) catch return vision.VisionError.OutOfMemory;
    var actual_count: usize = 0;

    for (0..count) |i| {
        const observation = objc.nsArrayObjectAtIndex(results, i);

        // Get payload string
        const payload_ns: ?objc.id = objc.msgSend(?objc.id, observation, objc.sel("payloadStringValue"), .{});
        const payload_cstr = if (payload_ns) |ns| objc.fromNSString(ns) else null;

        const payload_text = if (payload_cstr) |cstr| blk: {
            const len = std.mem.len(cstr);
            const copy = allocator.alloc(u8, len) catch return vision.VisionError.OutOfMemory;
            @memcpy(copy, cstr[0..len]);
            break :blk copy;
        } else blk: {
            const copy = allocator.alloc(u8, 0) catch return vision.VisionError.OutOfMemory;
            break :blk copy;
        };

        // Get symbology string and map to enum
        const symbology_ns = objc.msgSend(?objc.id, observation, objc.sel("symbology"), .{});
        const symbology = if (symbology_ns) |ns| mapSymbology(ns) else .unknown;

        // Bounding box
        const bbox = msgSendStret(CGRect, observation, objc.sel("boundingBox"));

        barcodes[actual_count] = .{
            .payload = payload_text,
            .symbology = symbology,
            .box = .{
                .x = bbox.origin_x,
                .y = 1.0 - bbox.origin_y - bbox.size_height,
                .width = bbox.size_width,
                .height = bbox.size_height,
            },
        };
        actual_count += 1;
    }

    if (actual_count < count) {
        return allocator.realloc(barcodes, actual_count) catch return barcodes[0..actual_count];
    }
    return barcodes;
}

fn mapSymbology(ns_symbology: objc.id) vision.Symbology {
    const cstr = objc.fromNSString(ns_symbology) orelse return .unknown;
    const s = std.mem.sliceTo(cstr, 0);

    // VNBarcodeSymbology strings: "VNBarcodeSymbologyQR", "VNBarcodeSymbologyEAN13", etc.
    if (std.mem.endsWith(u8, s, "QR")) return .qr;
    if (std.mem.endsWith(u8, s, "EAN13")) return .ean13;
    if (std.mem.endsWith(u8, s, "EAN8")) return .ean8;
    if (std.mem.endsWith(u8, s, "UPCA")) return .upca;
    if (std.mem.endsWith(u8, s, "UPCE")) return .upce;
    if (std.mem.endsWith(u8, s, "Code128")) return .code128;
    if (std.mem.endsWith(u8, s, "Code39")) return .code39;
    if (std.mem.endsWith(u8, s, "Code93")) return .code93;
    if (std.mem.endsWith(u8, s, "ITF14")) return .itf14;
    if (std.mem.endsWith(u8, s, "DataMatrix")) return .datamatrix;
    if (std.mem.endsWith(u8, s, "PDF417")) return .pdf417;
    if (std.mem.endsWith(u8, s, "Aztec")) return .aztec;
    return .unknown;
}
```

- [ ] **Step 2: Wire up `barcode` and `qr` subcommands in `main.zig`**

Both commands use the same logic. `qr` filters results to `symbology == .qr` only.

```zig
if (std.mem.eql(u8, command, "barcode") or std.mem.eql(u8, command, "qr")) {
    const qr_only = std.mem.eql(u8, command, "qr");
    var image_path: ?[]const u8 = null;
    var json_output = false;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (arg[0] != '-' and image_path == null) {
            image_path = arg;
        } else {
            try stderr.interface.print("Error: unknown flag: {s}\n", .{arg});
            try stderr.interface.flush();
            std.process.exit(2);
        }
    }

    const path = image_path orelse {
        try stderr.interface.print("Error: {s} requires an image path\n", .{command});
        try stderr.interface.flush();
        std.process.exit(2);
    };

    const handle = vision.loadImage(path) catch |err| {
        handleError(err, json_output, &stdout.interface, &stderr.interface);
        unreachable;
    };
    defer vision.freeImage(handle);

    const all_results = vision.scanBarcodes(allocator, handle) catch |err| {
        handleError(err, json_output, &stdout.interface, &stderr.interface);
        unreachable;
    };
    defer vision.freeResults(allocator, vision.BarcodeResult, all_results);

    // Filter to QR only if `loupe qr`
    // For display, we filter in the print functions rather than allocating a new slice
    if (json_output) {
        try printBarcodesJson(&stdout.interface, all_results, qr_only);
    } else {
        try printBarcodesHuman(&stdout.interface, all_results, qr_only);
    }

    try stdout.interface.flush();
    return;
}
```

Add output formatters:

```zig
fn symbologyName(s: vision.Symbology) []const u8 {
    return switch (s) {
        .qr => "QR",
        .ean13 => "EAN-13",
        .ean8 => "EAN-8",
        .upca => "UPC-A",
        .upce => "UPC-E",
        .code128 => "Code 128",
        .code39 => "Code 39",
        .code93 => "Code 93",
        .itf14 => "ITF-14",
        .datamatrix => "Data Matrix",
        .pdf417 => "PDF417",
        .aztec => "Aztec",
        .unknown => "Unknown",
    };
}

fn printBarcodesHuman(writer: *std.io.Writer, results: []const vision.BarcodeResult, qr_only: bool) !void {
    var printed: usize = 0;
    for (results) |r| {
        if (qr_only and r.symbology != .qr) continue;
        try writer.print("{s}: {s}\n", .{ symbologyName(r.symbology), r.payload });
        printed += 1;
    }
    if (printed == 0) {
        if (qr_only) {
            try writer.print("No QR codes detected.\n", .{});
        } else {
            try writer.print("No barcodes detected.\n", .{});
        }
    }
}

fn printBarcodesJson(writer: *std.io.Writer, results: []const vision.BarcodeResult, qr_only: bool) !void {
    try writer.print("{{\"barcodes\":[", .{});
    var first = true;
    for (results) |r| {
        if (qr_only and r.symbology != .qr) continue;
        if (!first) try writer.print(",", .{});
        try writer.print("{{\"payload\":\"", .{});
        try writeJsonString(writer, r.payload);
        try writer.print("\",\"symbology\":\"{s}\",\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d}}}", .{
            @tagName(r.symbology), r.box.x, r.box.y, r.box.width, r.box.height,
        });
        first = false;
    }
    try writer.print("]}}\n", .{});
}
```

- [ ] **Step 3: Test barcode scanning**

Run: `zig build run -- barcode /path/to/image-with-qr.png`
Expected: "QR: https://..." or similar decoded content.

Run: `zig build run -- qr /path/to/image-with-qr.png`
Expected: Same as above but only QR codes.

Run: `zig build run -- barcode /path/to/image-with-qr.png --json`
Expected: JSON with barcodes array.

Run: `zig build run -- barcode /path/to/no-barcodes.jpg`
Expected: "No barcodes detected."

Run: `zig build run -- qr /path/to/ean-barcode-only.jpg`
Expected: "No QR codes detected." (has barcode but not QR).

- [ ] **Step 4: Commit**

```bash
git add src/platform/macos.zig src/main.zig
git commit -m "feat: barcode and QR code scanning via macOS VNDetectBarcodesRequest"
```

---

### Task 7: C ABI Layer

**Files:**
- Modify: `src/c_api.zig` — full C ABI exports

Same pattern as copycat's `lib.zig`. Opaque handles, out-pointers, integer error codes, caller-freed memory via `loupe_free`.

- [ ] **Step 1: Implement C ABI exports**

```zig
const std = @import("std");
const vision = @import("vision");

const allocator = std.heap.c_allocator;

// --- Types ---

pub const LoupeFaceResult = extern struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    confidence: f64,
};

pub const LoupeOcrResult = extern struct {
    text: ?[*:0]const u8,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    confidence: f64,
};

pub const LoupeBarcodeResult = extern struct {
    payload: ?[*:0]const u8,
    symbology: ?[*:0]const u8,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

// --- Image lifecycle ---

export fn loupe_load_image(path: [*:0]const u8) ?*anyopaque {
    const path_slice = std.mem.sliceTo(path, 0);
    return vision.loadImage(path_slice) catch return null;
}

export fn loupe_free_image(handle: *anyopaque) void {
    vision.freeImage(handle);
}

export fn loupe_save_image(handle: *anyopaque, path: [*:0]const u8) i32 {
    const path_slice = std.mem.sliceTo(path, 0);
    vision.saveImage(handle, path_slice) catch return -1;
    return 0;
}

// --- Face detection ---

export fn loupe_detect_faces(
    handle: *anyopaque,
    out_faces: *?[*]LoupeFaceResult,
    out_count: *u32,
) i32 {
    const faces = vision.detectFaces(allocator, handle) catch return -1;

    if (faces.len == 0) {
        out_faces.* = null;
        out_count.* = 0;
        allocator.free(faces);
        return 0;
    }

    const c_faces = allocator.alloc(LoupeFaceResult, faces.len) catch {
        allocator.free(faces);
        return -1;
    };

    for (faces, 0..) |f, i| {
        c_faces[i] = .{
            .x = f.box.x,
            .y = f.box.y,
            .width = f.box.width,
            .height = f.box.height,
            .confidence = f.confidence,
        };
    }

    allocator.free(faces);
    out_faces.* = c_faces.ptr;
    out_count.* = @intCast(c_faces.len);
    return 0;
}

export fn loupe_blur_faces(
    handle: *anyopaque,
    faces: [*]const LoupeFaceResult,
    count: u32,
    mode: i32, // 0 = blur, 1 = redact
) ?*anyopaque {
    // Convert C face results to vision.FaceResult slice
    var zig_faces = allocator.alloc(vision.FaceResult, count) catch return null;
    defer allocator.free(zig_faces);

    for (0..count) |i| {
        zig_faces[i] = .{
            .box = .{
                .x = faces[i].x,
                .y = faces[i].y,
                .width = faces[i].width,
                .height = faces[i].height,
            },
            .confidence = faces[i].confidence,
        };
    }

    const blur_mode: vision.BlurMode = if (mode == 0) .blur else .redact;
    return vision.blurFaces(handle, zig_faces, blur_mode) catch return null;
}

// --- OCR ---

export fn loupe_recognize_text(
    handle: *anyopaque,
    out_results: *?[*]LoupeOcrResult,
    out_count: *u32,
) i32 {
    const results = vision.recognizeText(allocator, handle) catch return -1;

    if (results.len == 0) {
        out_results.* = null;
        out_count.* = 0;
        vision.freeResults(allocator, vision.OcrResult, results);
        return 0;
    }

    const c_results = allocator.alloc(LoupeOcrResult, results.len) catch {
        vision.freeResults(allocator, vision.OcrResult, results);
        return -1;
    };

    for (results, 0..) |r, i| {
        // Copy text as null-terminated C string
        const c_text = allocator.allocSentinel(u8, r.text.len, 0) catch {
            // Clean up already converted results
            for (0..i) |j| {
                if (c_results[j].text) |t| std.c.free(@constCast(@ptrCast(t)));
            }
            allocator.free(c_results);
            vision.freeResults(allocator, vision.OcrResult, results);
            return -1;
        };
        @memcpy(c_text[0..r.text.len], r.text);

        c_results[i] = .{
            .text = c_text,
            .x = r.box.x,
            .y = r.box.y,
            .width = r.box.width,
            .height = r.box.height,
            .confidence = r.confidence,
        };
    }

    vision.freeResults(allocator, vision.OcrResult, results);
    out_results.* = c_results.ptr;
    out_count.* = @intCast(c_results.len);
    return 0;
}

// --- Barcode scanning ---

export fn loupe_scan_barcodes(
    handle: *anyopaque,
    out_results: *?[*]LoupeBarcodeResult,
    out_count: *u32,
) i32 {
    const results = vision.scanBarcodes(allocator, handle) catch return -1;

    if (results.len == 0) {
        out_results.* = null;
        out_count.* = 0;
        vision.freeResults(allocator, vision.BarcodeResult, results);
        return 0;
    }

    const c_results = allocator.alloc(LoupeBarcodeResult, results.len) catch {
        vision.freeResults(allocator, vision.BarcodeResult, results);
        return -1;
    };

    for (results, 0..) |r, i| {
        const c_payload = allocator.allocSentinel(u8, r.payload.len, 0) catch {
            for (0..i) |j| {
                if (c_results[j].payload) |p| std.c.free(@constCast(@ptrCast(p)));
                if (c_results[j].symbology) |s| std.c.free(@constCast(@ptrCast(s)));
            }
            allocator.free(c_results);
            vision.freeResults(allocator, vision.BarcodeResult, results);
            return -1;
        };
        @memcpy(c_payload[0..r.payload.len], r.payload);

        const sym_name = @tagName(r.symbology);
        const c_sym = allocator.allocSentinel(u8, sym_name.len, 0) catch {
            std.c.free(@constCast(@ptrCast(c_payload)));
            for (0..i) |j| {
                if (c_results[j].payload) |p| std.c.free(@constCast(@ptrCast(p)));
                if (c_results[j].symbology) |s| std.c.free(@constCast(@ptrCast(s)));
            }
            allocator.free(c_results);
            vision.freeResults(allocator, vision.BarcodeResult, results);
            return -1;
        };
        @memcpy(c_sym[0..sym_name.len], sym_name);

        c_results[i] = .{
            .payload = c_payload,
            .symbology = c_sym,
            .x = r.box.x,
            .y = r.box.y,
            .width = r.box.width,
            .height = r.box.height,
        };
    }

    vision.freeResults(allocator, vision.BarcodeResult, results);
    out_results.* = c_results.ptr;
    out_count.* = @intCast(c_results.len);
    return 0;
}

// --- Memory management ---

export fn loupe_free(ptr: ?*anyopaque) void {
    if (ptr) |p| {
        std.c.free(p);
    }
}

/// Free an array of OCR results (frees each text string, then the array).
export fn loupe_free_ocr_results(results: [*]LoupeOcrResult, count: u32) void {
    for (0..count) |i| {
        if (results[i].text) |t| std.c.free(@constCast(@ptrCast(t)));
    }
    std.c.free(@ptrCast(results));
}

/// Free an array of barcode results (frees each payload/symbology string, then the array).
export fn loupe_free_barcode_results(results: [*]LoupeBarcodeResult, count: u32) void {
    for (0..count) |i| {
        if (results[i].payload) |p| std.c.free(@constCast(@ptrCast(p)));
        if (results[i].symbology) |s| std.c.free(@constCast(@ptrCast(s)));
    }
    std.c.free(@ptrCast(results));
}
```

- [ ] **Step 2: Verify build**

Run: `zig build`
Expected: Compiles without errors. Produces `zig-out/lib/libloupe.dylib` and `zig-out/bin/loupe`.

- [ ] **Step 3: Commit**

```bash
git add src/c_api.zig
git commit -m "feat: C ABI layer with opaque handles for FFI consumers"
```

---

### Task 8: Polish & README

**Files:**
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `README.md`

- [ ] **Step 1: Create `.gitignore`**

```
.DS_Store
.zig-cache
zig-out
docs/superpowers/
docs/specs/
docs/plans/
node_modules/
```

- [ ] **Step 2: Create `LICENSE` (MIT)**

Same as copycat/whereami. MIT license, George Mandis, 2026.

- [ ] **Step 3: Create `README.md`**

Basic README with:
- Project description
- Install from source instructions (`zig build`)
- CLI usage examples for all commands
- Platform support table (macOS ✅, Windows planned, Linux N/A)
- C ABI overview (brief, pointing to `c_api.zig`)
- License

- [ ] **Step 4: Commit**

```bash
git add .gitignore LICENSE README.md
git commit -m "docs: README, LICENSE, and .gitignore"
```

---

### Task 9: Integration Testing & Final Verification

**Files:**
- No new files — manual testing of all commands

- [ ] **Step 1: Gather test images**

Need at minimum:
- A photo with faces (for faces/blur/redact)
- A screenshot or document image with text (for OCR)
- An image containing a QR code (for barcode/qr)
- An image with no faces/text/barcodes (for empty-result paths)
- A non-image file (for error path)

- [ ] **Step 2: Test all commands end-to-end**

```bash
# Face detection
zig build run -- faces photo.jpg
zig build run -- faces photo.jpg --json
zig build run -- faces photo.jpg -o blurred.jpg --blur
zig build run -- faces photo.jpg -o redacted.png --redact

# OCR
zig build run -- ocr screenshot.png
zig build run -- ocr screenshot.png --json

# Barcode
zig build run -- barcode qr-image.png
zig build run -- barcode qr-image.png --json
zig build run -- qr qr-image.png

# Error cases
zig build run -- faces nonexistent.jpg
zig build run -- faces photo.jpg --blur  # missing -o
zig build run -- unknown-command

# Help
zig build run -- --help
zig build run
```

- [ ] **Step 3: Verify shared library builds**

```bash
zig build
ls -la zig-out/lib/libloupe.dylib
ls -la zig-out/bin/loupe
```

- [ ] **Step 4: Fix any issues found during testing**

Address compilation errors, incorrect coordinate transforms, missing error handling, or output formatting issues.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "fix: integration test fixes"
```
