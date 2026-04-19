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

extern "c" fn CGBitmapContextCreate(data: ?*anyopaque, width: usize, height: usize, bitsPerComponent: usize, bytesPerRow: usize, space: *anyopaque, bitmapInfo: u32) ?*anyopaque;
extern "c" fn CGBitmapContextCreateImage(context: *anyopaque) ?*anyopaque;
extern "c" fn CGContextDrawImage(context: *anyopaque, rect: CGRect, image: *anyopaque) void;
extern "c" fn CGContextSetRGBFillColor(context: *anyopaque, r: f64, g: f64, b: f64, a: f64) void;
extern "c" fn CGContextFillRect(context: *anyopaque, rect: CGRect) void;
extern "c" fn CGContextRelease(context: *anyopaque) void;
extern "c" fn CGColorSpaceCreateDeviceRGB() ?*anyopaque;
extern "c" fn CGColorSpaceRelease(space: *anyopaque) void;
extern "c" fn CGImageCreateWithImageInRect(image: *anyopaque, rect: CGRect) ?*anyopaque;

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
const kCGImageAlphaPremultipliedLast: u32 = 1;

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

    // Release alloc+init objects (handler and request own +1 retain count)
    objc.msgSend(void, handler, objc.sel("release"), .{});
    objc.msgSend(void, request, objc.sel("release"), .{});

    return faces;
}

pub fn recognizeText(allocator: Allocator, image: ImageHandle) vision.VisionError![]vision.OcrResult {
    // 1. Create empty NSDictionary for options
    const NSDictionary = objc.getClass("NSDictionary") orelse return vision.VisionError.DetectionFailed;
    const empty_dict = objc.msgSend(objc.id, NSDictionary, objc.sel("dictionary"), .{});

    // 2. Create VNImageRequestHandler from CGImage
    const HandlerClass = objc.getClass("VNImageRequestHandler") orelse return vision.VisionError.DetectionFailed;
    const handler_alloc = objc.msgSend(objc.id, HandlerClass, objc.sel("alloc"), .{});
    const image_as_id: objc.id = @ptrCast(image);
    const handler = objc.msgSend(objc.id, handler_alloc, objc.sel("initWithCGImage:options:"), .{ image_as_id, empty_dict });

    // 3. Create VNRecognizeTextRequest
    const RequestClass = objc.getClass("VNRecognizeTextRequest") orelse return vision.VisionError.DetectionFailed;
    const request_alloc = objc.msgSend(objc.id, RequestClass, objc.sel("alloc"), .{});
    const request = objc.msgSend(objc.id, request_alloc, objc.sel("init"), .{});

    // 4. Set recognition level to accurate (1)
    const set_level_fn: *const fn (objc.id, objc.SEL, i64) callconv(.c) void = @ptrCast(&objc_msgSend);
    set_level_fn(request, objc.sel("setRecognitionLevel:"), @as(i64, 1));

    // 5. Wrap request in NSArray and perform
    const NSArray = objc.getClass("NSArray") orelse return vision.VisionError.DetectionFailed;
    const requests_array = objc.msgSend(objc.id, NSArray, objc.sel("arrayWithObject:"), .{request});

    var err_ptr: ?objc.id = null;
    const perform_fn: *const fn (objc.id, objc.SEL, objc.id, *?objc.id) callconv(.c) bool = @ptrCast(&objc_msgSend);
    const success = perform_fn(handler, objc.sel("performRequests:error:"), requests_array, &err_ptr);
    if (!success) return vision.VisionError.DetectionFailed;

    // 6. Get results — NSArray of VNRecognizedTextObservation
    const results = objc.msgSend(objc.id, request, objc.sel("results"), .{});
    const count = objc.nsArrayCount(results);

    if (count == 0) {
        objc.msgSend(void, handler, objc.sel("release"), .{});
        objc.msgSend(void, request, objc.sel("release"), .{});
        return allocator.alloc(vision.OcrResult, 0) catch return vision.VisionError.OutOfMemory;
    }

    // Allocate output slice (may shrink if some observations have no candidates)
    const ocr_results = allocator.alloc(vision.OcrResult, count) catch return vision.VisionError.OutOfMemory;
    var actual_count: usize = 0;

    // 7. Iterate observations
    for (0..count) |i| {
        const observation = objc.nsArrayObjectAtIndex(results, i);

        // Get top candidate: [observation topCandidates:1]
        const top_candidates_fn: *const fn (objc.id, objc.SEL, objc.NSUInteger) callconv(.c) objc.id = @ptrCast(&objc_msgSend);
        const candidates = top_candidates_fn(observation, objc.sel("topCandidates:"), @as(objc.NSUInteger, 1));
        const cand_count = objc.nsArrayCount(candidates);
        if (cand_count == 0) continue;

        const candidate = objc.nsArrayObjectAtIndex(candidates, 0);

        // Get text string from candidate
        const ns_str = objc.msgSend(objc.id, candidate, objc.sel("string"), .{});
        const c_str = objc.fromNSString(ns_str) orelse continue;
        const text_len = std.mem.len(c_str);

        // Copy text into heap-allocated Zig slice
        const text_copy = allocator.alloc(u8, text_len) catch {
            // Free any already-allocated text entries and the slice
            for (0..actual_count) |j| allocator.free(ocr_results[j].text);
            allocator.free(ocr_results);
            objc.msgSend(void, handler, objc.sel("release"), .{});
            objc.msgSend(void, request, objc.sel("release"), .{});
            return vision.VisionError.OutOfMemory;
        };
        @memcpy(text_copy, c_str[0..text_len]);

        // Get confidence
        const confidence = objc.msgSend(f32, candidate, objc.sel("confidence"), .{});

        // Get bounding box from observation and flip Y coordinate
        const bbox = getBoundingBox(observation);
        const y_flipped = 1.0 - bbox.origin_y - bbox.size_height;

        ocr_results[actual_count] = .{
            .text = text_copy,
            .box = .{
                .x = bbox.origin_x,
                .y = y_flipped,
                .width = bbox.size_width,
                .height = bbox.size_height,
            },
            .confidence = @floatCast(confidence),
        };
        actual_count += 1;
    }

    // Release alloc+init objects
    objc.msgSend(void, handler, objc.sel("release"), .{});
    objc.msgSend(void, request, objc.sel("release"), .{});

    // Return a trimmed slice if some observations were skipped
    if (actual_count < count) {
        const trimmed = allocator.realloc(ocr_results, actual_count) catch ocr_results[0..actual_count];
        return trimmed;
    }

    return ocr_results;
}

pub fn scanBarcodes(allocator: Allocator, image: ImageHandle) vision.VisionError![]vision.BarcodeResult {
    _ = allocator;
    _ = image;
    return vision.VisionError.UnsupportedPlatform;
}

// ---------------------------------------------------------------------------
// Blur/Redact helpers
// ---------------------------------------------------------------------------

/// Helper: convert normalized top-left face coords to CG bottom-left pixel CGRect.
fn faceRectToPixels(face: vision.FaceResult, width_f: f64, height_f: f64) CGRect {
    const px = face.box.x * width_f;
    const pw = face.box.width * width_f;
    const ph = face.box.height * height_f;
    const py = (1.0 - face.box.y - face.box.height) * height_f; // flip to bottom-left
    return .{ .origin_x = px, .origin_y = py, .size_width = pw, .size_height = ph };
}

/// Typed objc_msgSend for CIContext createCGImage:fromRect: (needs CGRect arg).
fn ciContextCreateCGImage(ctx: objc.id, ci_image: objc.id, rect: CGRect) ?*anyopaque {
    const func: *const fn (objc.id, objc.SEL, objc.id, CGRect) callconv(.c) ?*anyopaque = @ptrCast(&objc_msgSend);
    return func(ctx, objc.sel("createCGImage:fromRect:"), ci_image, rect);
}

/// Typed objc_msgSend for CIImage extent (returns CGRect).
fn getCIImageExtent(ci_image: objc.id) CGRect {
    const func: *const fn (objc.id, objc.SEL) callconv(.c) CGRect = @ptrCast(&objc_msgSend);
    return func(ci_image, objc.sel("extent"));
}

/// Create a bitmap context with the original image drawn into it.
fn createBitmapContextWithImage(image: ImageHandle, width: usize, height: usize) vision.VisionError!struct { ctx: *anyopaque, color_space: *anyopaque } {
    const color_space = CGColorSpaceCreateDeviceRGB() orelse return vision.VisionError.DetectionFailed;
    errdefer CGColorSpaceRelease(color_space);

    const ctx = CGBitmapContextCreate(
        null,
        width,
        height,
        8,
        width * 4,
        color_space,
        kCGImageAlphaPremultipliedLast,
    ) orelse {
        CGColorSpaceRelease(color_space);
        return vision.VisionError.DetectionFailed;
    };

    const width_f: f64 = @floatFromInt(width);
    const height_f: f64 = @floatFromInt(height);
    const full_rect = CGRect{ .origin_x = 0, .origin_y = 0, .size_width = width_f, .size_height = height_f };
    CGContextDrawImage(ctx, full_rect, image);

    return .{ .ctx = ctx, .color_space = color_space };
}

pub fn blurFaces(allocator: Allocator, image: ImageHandle, faces: []const vision.FaceResult, mode: vision.BlurMode) vision.VisionError!ImageHandle {
    _ = allocator;

    const width = CGImageGetWidth(image);
    const height = CGImageGetHeight(image);
    const width_f: f64 = @floatFromInt(width);
    const height_f: f64 = @floatFromInt(height);

    const bmp = try createBitmapContextWithImage(image, width, height);
    const ctx = bmp.ctx;
    const color_space = bmp.color_space;
    defer CGContextRelease(ctx);
    defer CGColorSpaceRelease(color_space);

    switch (mode) {
        .redact => {
            // Draw black rectangles over each face
            CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
            for (faces) |face| {
                const face_rect = faceRectToPixels(face, width_f, height_f);
                CGContextFillRect(ctx, face_rect);
            }
        },
        .blur => {
            // For each face: crop, blur with CIGaussianBlur, draw back
            const CIImage = objc.getClass("CIImage") orelse return vision.VisionError.DetectionFailed;
            const CIFilter = objc.getClass("CIFilter") orelse return vision.VisionError.DetectionFailed;
            const CIContext = objc.getClass("CIContext") orelse return vision.VisionError.DetectionFailed;
            const NSNumber = objc.getClass("NSNumber") orelse return vision.VisionError.DetectionFailed;

            // Create a shared CIContext for rendering
            const ci_ctx = objc.msgSend(objc.id, CIContext, objc.sel("context"), .{});

            for (faces) |face| {
                const face_rect = faceRectToPixels(face, width_f, height_f);

                // 1. Crop face from original CGImage
                const cropped = CGImageCreateWithImageInRect(image, face_rect) orelse continue;
                defer CGImageRelease(cropped);

                // 2. Create CIImage from cropped CGImage
                const cropped_as_id: objc.id = @ptrCast(cropped);
                const ci_image = objc.msgSend(objc.id, CIImage, objc.sel("imageWithCGImage:"), .{cropped_as_id});

                // 3. Create CIGaussianBlur filter
                const filter_name = objc.nsString("CIGaussianBlur");
                const filter = objc.msgSend(objc.id, CIFilter, objc.sel("filterWithName:"), .{filter_name});

                // 4. Set defaults
                objc.msgSend(void, filter, objc.sel("setDefaults"), .{});

                // 5. Set input image
                const input_image_key = objc.nsString("inputImage");
                objc.msgSend(void, filter, objc.sel("setValue:forKey:"), .{ ci_image, input_image_key });

                // 6. Set blur radius
                const input_radius_key = objc.nsString("inputRadius");
                const radius_value = objc.msgSend(objc.id, NSNumber, objc.sel("numberWithFloat:"), .{@as(f32, 20.0)});
                objc.msgSend(void, filter, objc.sel("setValue:forKey:"), .{ radius_value, input_radius_key });

                // 7. Get output CIImage
                const output_ci = objc.msgSend(objc.id, filter, objc.sel("outputImage"), .{});

                // 8. Render to CGImage using the INPUT image's extent (not output's,
                //    since blur expands the bounds)
                const input_extent = getCIImageExtent(ci_image);
                const blurred_cg = ciContextCreateCGImage(ci_ctx, output_ci, input_extent) orelse continue;
                defer CGImageRelease(blurred_cg);

                // 9. Draw blurred face back into bitmap context at face position
                CGContextDrawImage(ctx, face_rect, blurred_cg);
            }
        },
    }

    // Create result image from bitmap context
    const result = CGBitmapContextCreateImage(ctx) orelse return vision.VisionError.DetectionFailed;
    return result;
}

// freeResults is handled in vision.zig directly — no platform dispatch needed.
