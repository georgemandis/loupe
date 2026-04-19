// macOS platform implementation — image I/O via CoreFoundation/ImageIO/CoreGraphics.
// Face detection, OCR, barcode scanning, and blur are stubs for later tasks.

const std = @import("std");
const Allocator = std.mem.Allocator;
const vision = @import("../vision.zig");
const objc = @import("../objc.zig");

// ---------------------------------------------------------------------------
// CoreFoundation / ImageIO / CoreGraphics extern declarations
// ---------------------------------------------------------------------------

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

extern "c" fn CGImageSourceCreateWithURL(
    url: *anyopaque,
    options: ?*anyopaque,
) ?*anyopaque;

extern "c" fn CGImageSourceCreateImageAtIndex(
    source: *anyopaque,
    index: usize,
    options: ?*anyopaque,
) ?*anyopaque;

extern "c" fn CGImageRelease(image: *anyopaque) void;

extern "c" fn CGImageGetWidth(image: *anyopaque) usize;
extern "c" fn CGImageGetHeight(image: *anyopaque) usize;

extern "c" fn CGImageDestinationCreateWithURL(
    url: *anyopaque,
    image_type: *anyopaque,
    count: usize,
    options: ?*anyopaque,
) ?*anyopaque;

extern "c" fn CGImageDestinationAddImage(
    dest: *anyopaque,
    image: *anyopaque,
    properties: ?*anyopaque,
) void;

extern "c" fn CGImageDestinationFinalize(dest: *anyopaque) bool;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const kCFStringEncodingUTF8: u32 = 0x08000100;
const kCFURLPOSIXPathStyle: i64 = 0;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub const ImageHandle = *anyopaque;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Create a CFStringRef from a Zig byte slice. Caller must CFRelease the result.
fn cfStringFromBytes(bytes: []const u8) ?*anyopaque {
    return CFStringCreateWithBytes(
        null,
        bytes.ptr,
        @intCast(bytes.len),
        kCFStringEncodingUTF8,
        false,
    );
}

/// Create a CFURLRef (file URL) from a Zig path slice. Caller must CFRelease the result.
fn cfURLFromPath(path: []const u8) ?*anyopaque {
    const cf_path = cfStringFromBytes(path) orelse return null;
    defer CFRelease(cf_path);

    return CFURLCreateWithFileSystemPath(
        null,
        cf_path,
        kCFURLPOSIXPathStyle,
        false,
    );
}

// ---------------------------------------------------------------------------
// Image I/O
// ---------------------------------------------------------------------------

pub fn loadImage(path: []const u8) vision.VisionError!ImageHandle {
    // Step 1: path → CFURLRef
    const url = cfURLFromPath(path) orelse return vision.VisionError.ImageLoadFailed;
    defer CFRelease(url);

    // Step 2: CFURLRef → CGImageSourceRef
    const source = CGImageSourceCreateWithURL(url, null) orelse return vision.VisionError.ImageLoadFailed;
    defer CFRelease(source);

    // Step 3: CGImageSourceRef → CGImageRef (first image in the source)
    const image = CGImageSourceCreateImageAtIndex(source, 0, null) orelse return vision.VisionError.ImageLoadFailed;

    return image;
}

pub fn freeImage(image: ImageHandle) void {
    CGImageRelease(image);
}

pub fn saveImage(image: ImageHandle, path: []const u8) vision.VisionError!void {
    // Step 1: path → CFURLRef
    const url = cfURLFromPath(path) orelse return vision.VisionError.SaveFailed;
    defer CFRelease(url);

    // Step 2: determine UTI from file extension
    const uti_str: []const u8 = blk: {
        if (std.mem.endsWith(u8, path, ".png")) {
            break :blk "public.png";
        } else if (std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg")) {
            break :blk "public.jpeg";
        } else {
            return vision.VisionError.UnsupportedFormat;
        }
    };

    // Step 3: UTI string → CFStringRef
    const uti = cfStringFromBytes(uti_str) orelse return vision.VisionError.SaveFailed;
    defer CFRelease(uti);

    // Step 4: create CGImageDestinationRef
    const dest = CGImageDestinationCreateWithURL(url, uti, 1, null) orelse return vision.VisionError.SaveFailed;
    defer CFRelease(dest);

    // Step 5: add the image
    CGImageDestinationAddImage(dest, image, null);

    // Step 6: finalize (flush to disk)
    const ok = CGImageDestinationFinalize(dest);
    if (!ok) return vision.VisionError.SaveFailed;
}

// ---------------------------------------------------------------------------
// Stubs for later tasks
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Vision framework helpers for face detection
// ---------------------------------------------------------------------------

const CGRect = extern struct {
    origin_x: f64,
    origin_y: f64,
    size_width: f64,
    size_height: f64,
};

// We need a typed cast of objc_msgSend that returns CGRect (32 bytes, fits in
// 4 ARM64 registers so regular objc_msgSend works — no _stret needed).
extern "objc" fn objc_msgSend() void;

fn getBoundingBox(observation: objc.id) CGRect {
    const func: *const fn (objc.id, objc.SEL) callconv(.c) CGRect = @ptrCast(&objc_msgSend);
    return func(observation, objc.sel("boundingBox"));
}

pub fn detectFaces(allocator: Allocator, image: ImageHandle) vision.VisionError![]vision.FaceResult {
    // 1. Create empty NSDictionary for options
    const NSDictionary = objc.getClass("NSDictionary") orelse return vision.VisionError.DetectionFailed;
    const empty_dict = objc.msgSend(objc.id, NSDictionary, objc.sel("dictionary"), .{});

    // 2. Create VNImageRequestHandler from CGImage
    const HandlerClass = objc.getClass("VNImageRequestHandler") orelse return vision.VisionError.DetectionFailed;
    const handler_alloc = objc.msgSend(objc.id, HandlerClass, objc.sel("alloc"), .{});
    const image_as_id: objc.id = @ptrCast(image);
    const handler = objc.msgSend(objc.id, handler_alloc, objc.sel("initWithCGImage:options:"), .{ image_as_id, empty_dict });

    // 3. Create VNDetectFaceRectanglesRequest
    const RequestClass = objc.getClass("VNDetectFaceRectanglesRequest") orelse return vision.VisionError.DetectionFailed;
    const request_alloc = objc.msgSend(objc.id, RequestClass, objc.sel("alloc"), .{});
    const request = objc.msgSend(objc.id, request_alloc, objc.sel("init"), .{});

    // 4. Wrap request in NSArray
    const NSArray = objc.getClass("NSArray") orelse return vision.VisionError.DetectionFailed;
    const requests_array = objc.msgSend(objc.id, NSArray, objc.sel("arrayWithObject:"), .{request});

    // 5. Perform requests
    var err_ptr: ?objc.id = null;
    const perform_fn: *const fn (objc.id, objc.SEL, objc.id, *?objc.id) callconv(.c) bool = @ptrCast(&objc_msgSend);
    const success = perform_fn(handler, objc.sel("performRequests:error:"), requests_array, &err_ptr);
    if (!success) return vision.VisionError.DetectionFailed;

    // 6. Get results — NSArray of VNFaceObservation
    const results = objc.msgSend(objc.id, request, objc.sel("results"), .{});
    const count = objc.nsArrayCount(results);

    if (count == 0) {
        return allocator.alloc(vision.FaceResult, 0) catch return vision.VisionError.OutOfMemory;
    }

    // 7. Allocate output slice and populate
    const faces = allocator.alloc(vision.FaceResult, count) catch return vision.VisionError.OutOfMemory;

    for (0..count) |i| {
        const observation = objc.nsArrayObjectAtIndex(results, i);
        const bbox = getBoundingBox(observation);
        const confidence = objc.msgSend(f32, observation, objc.sel("confidence"), .{});

        // Vision uses bottom-left origin; flip to top-left
        const y_flipped = 1.0 - bbox.origin_y - bbox.size_height;

        faces[i] = .{
            .box = .{
                .x = bbox.origin_x,
                .y = y_flipped,
                .width = bbox.size_width,
                .height = bbox.size_height,
            },
            .confidence = @floatCast(confidence),
        };
    }

    return faces;
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

// freeResults is handled in vision.zig directly — no platform dispatch needed.
