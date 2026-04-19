const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const platform = switch (builtin.os.tag) {
    .macos => @import("platform/macos.zig"),
    .windows => @import("platform/windows.zig"),
    else => @compileError("Unsupported platform. Currently supported: macOS, Windows."),
};

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

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

/// Platform-specific image handle. On macOS this will be a CGImageRef.
pub const ImageHandle = platform.ImageHandle;

pub const VisionError = error{
    ImageLoadFailed,
    UnsupportedFormat,
    DetectionFailed,
    SaveFailed,
    UnsupportedPlatform,
    OutOfMemory,
};

// ---------------------------------------------------------------------------
// Platform dispatch functions
// ---------------------------------------------------------------------------

pub fn loadImage(allocator: Allocator, path: []const u8) VisionError!ImageHandle {
    return platform.loadImage(allocator, path);
}

pub fn detectFaces(allocator: Allocator, image: ImageHandle) VisionError![]FaceResult {
    return platform.detectFaces(allocator, image);
}

pub fn recognizeText(allocator: Allocator, image: ImageHandle) VisionError![]OcrResult {
    return platform.recognizeText(allocator, image);
}

pub fn scanBarcodes(allocator: Allocator, image: ImageHandle) VisionError![]BarcodeResult {
    return platform.scanBarcodes(allocator, image);
}

pub fn blurFaces(allocator: Allocator, image: ImageHandle, faces: []const FaceResult, mode: BlurMode) VisionError!ImageHandle {
    return platform.blurFaces(allocator, image, faces, mode);
}

pub fn saveImage(allocator: Allocator, image: ImageHandle, path: []const u8) VisionError!void {
    return platform.saveImage(allocator, image, path);
}

pub fn freeImage(image: ImageHandle) void {
    platform.freeImage(image);
}

pub fn freeResults(allocator: Allocator, results: anytype) void {
    platform.freeResults(allocator, results);
}
