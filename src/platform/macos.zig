// macOS platform stub — all operations return VisionError.UnsupportedPlatform
// until the real Vision framework integration is implemented in later tasks.

const std = @import("std");
const Allocator = std.mem.Allocator;
const vision = @import("../vision.zig");

pub const ImageHandle = *anyopaque;

pub fn loadImage(path: []const u8) vision.VisionError!ImageHandle {
    _ = path;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn detectFaces(allocator: Allocator, image: ImageHandle) vision.VisionError![]vision.FaceResult {
    _ = allocator;
    _ = image;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn recognizeText(allocator: Allocator, image: ImageHandle) vision.VisionError![]vision.OcrResult {
    _ = allocator;
    _ = image;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn scanBarcodes(allocator: Allocator, image: ImageHandle) vision.VisionError![]vision.BarcodeResult {
    _ = allocator;
    _ = image;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn blurFaces(allocator: Allocator, image: ImageHandle, faces: []const vision.FaceResult, mode: vision.BlurMode) vision.VisionError!ImageHandle {
    _ = allocator;
    _ = image;
    _ = faces;
    _ = mode;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn saveImage(image: ImageHandle, path: []const u8) vision.VisionError!void {
    _ = image;
    _ = path;
    return vision.VisionError.UnsupportedPlatform;
}

pub fn freeImage(image: ImageHandle) void {
    _ = image;
    // no-op in stub
}

// freeResults is now handled in vision.zig directly — no platform dispatch needed.
