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

pub const LoupeArucoResult = extern struct {
    id: u32,
    dictionary: ?[*:0]const u8,
    /// Corner coordinates as x0,y0,x1,y1,x2,y2,x3,y3 — normalized, top-left
    /// origin, canonical marker order (corner 0 = marker top-left), clockwise.
    corners: [8]f64,
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

/// Flag for `loupe_load_image_ex`: apply the orientation stored in the
/// file's metadata, so a phone photo comes back upright.
pub const LOUPE_LOAD_APPLY_ORIENTATION: u32 = 1 << 0;

export fn loupe_load_image_ex(path: [*:0]const u8, flags: u32) ?*anyopaque {
    const path_slice = std.mem.sliceTo(path, 0);
    if (flags & LOUPE_LOAD_APPLY_ORIENTATION != 0) {
        return vision.loadImageOriented(path_slice) catch return null;
    }
    return vision.loadImage(path_slice) catch return null;
}

/// Render an image to 8-bit sRGB RGBA pixels (straight alpha, top row
/// first, `width * height * 4` bytes). Free the result with `loupe_free`.
export fn loupe_image_rgba(handle: *anyopaque, out_width: *u32, out_height: *u32) ?[*]u8 {
    const px = vision.getRgbaPixels(allocator, handle) catch return null;
    out_width.* = @intCast(px.width);
    out_height.* = @intCast(px.height);
    return px.data.ptr;
}

// --- Background removal ---

pub const LOUPE_OK: i32 = 0;
pub const LOUPE_ERR_FAILED: i32 = -1;
pub const LOUPE_ERR_UNSUPPORTED: i32 = -2;
pub const LOUPE_ERR_NO_SUBJECT: i32 = -3;

/// Lift the foreground subjects out of an image. On success returns 0 and
/// stores a new image (same size, transparent background) in `out_image`;
/// free it with `loupe_free_image`. Returns LOUPE_ERR_NO_SUBJECT when
/// nothing stands out from the background and LOUPE_ERR_UNSUPPORTED where
/// the system cannot do this (before macOS 14, and on Windows).
export fn loupe_remove_background(handle: *anyopaque, out_image: *?*anyopaque) i32 {
    out_image.* = null;
    out_image.* = vision.removeBackground(handle) catch |err| return switch (err) {
        error.NoSubject => LOUPE_ERR_NO_SUBJECT,
        error.UnsupportedPlatform => LOUPE_ERR_UNSUPPORTED,
        else => LOUPE_ERR_FAILED,
    };
    return LOUPE_OK;
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
    return vision.blurFaces(allocator, handle, zig_faces, blur_mode) catch return null;
}

// --- OCR ---

/// Flag for `loupe_recognize_text_ex`: return the characters as read, with
/// no dictionary-based correction. Use for code and identifiers.
pub const LOUPE_OCR_NO_LANGUAGE_CORRECTION: u32 = 1 << 0;

export fn loupe_recognize_text(
    handle: *anyopaque,
    out_results: *?[*]LoupeOcrResult,
    out_count: *u32,
) i32 {
    return loupe_recognize_text_ex(handle, 0, out_results, out_count);
}

/// `loupe_recognize_text` with option flags (LOUPE_OCR_*). Unknown flags are
/// ignored. Results are freed with `loupe_free_ocr_results`.
export fn loupe_recognize_text_ex(
    handle: *anyopaque,
    flags: u32,
    out_results: *?[*]LoupeOcrResult,
    out_count: *u32,
) i32 {
    const options = vision.OcrOptions{
        .language_correction = (flags & LOUPE_OCR_NO_LANGUAGE_CORRECTION) == 0,
    };
    const results = vision.recognizeTextWithOptions(allocator, handle, options) catch return -1;

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
                if (c_results[j].text) |t| allocator.free(t[0..std.mem.len(t)]);
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
                if (c_results[j].payload) |p| allocator.free(p[0..std.mem.len(p)]);
                if (c_results[j].symbology) |s| allocator.free(s[0..std.mem.len(s)]);
            }
            allocator.free(c_results);
            vision.freeResults(allocator, vision.BarcodeResult, results);
            return -1;
        };
        @memcpy(c_payload[0..r.payload.len], r.payload);

        const sym_name = @tagName(r.symbology);
        const c_sym = allocator.allocSentinel(u8, sym_name.len, 0) catch {
            allocator.free(c_payload[0 .. r.payload.len + 1]);
            for (0..i) |j| {
                if (c_results[j].payload) |p| allocator.free(p[0..std.mem.len(p)]);
                if (c_results[j].symbology) |s| allocator.free(s[0..std.mem.len(s)]);
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

// --- ArUco marker detection ---

export fn loupe_detect_aruco(
    handle: *anyopaque,
    out_results: *?[*]LoupeArucoResult,
    out_count: *u32,
) i32 {
    const results = vision.detectAruco(allocator, handle, .{}) catch return -1;
    defer vision.freeResults(allocator, vision.ArucoResult, results);

    if (results.len == 0) {
        out_results.* = null;
        out_count.* = 0;
        return 0;
    }

    const c_results = allocator.alloc(LoupeArucoResult, results.len) catch return -1;

    for (results, 0..) |r, i| {
        const c_dict = allocator.allocSentinel(u8, r.dictionary.len, 0) catch {
            for (0..i) |j| {
                if (c_results[j].dictionary) |d| allocator.free(d[0..std.mem.len(d)]);
            }
            allocator.free(c_results);
            return -1;
        };
        @memcpy(c_dict[0..r.dictionary.len], r.dictionary);

        var corners: [8]f64 = undefined;
        for (r.corners, 0..) |p, j| {
            corners[j * 2] = p.x;
            corners[j * 2 + 1] = p.y;
        }

        c_results[i] = .{
            .id = r.id,
            .dictionary = c_dict,
            .corners = corners,
            .x = r.box.x,
            .y = r.box.y,
            .width = r.box.width,
            .height = r.box.height,
        };
    }

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
        if (results[i].text) |t| std.c.free(@ptrCast(@constCast(t)));
    }
    std.c.free(@ptrCast(results));
}

/// Free an array of barcode results (frees each payload/symbology string, then the array).
export fn loupe_free_barcode_results(results: [*]LoupeBarcodeResult, count: u32) void {
    for (0..count) |i| {
        if (results[i].payload) |p| std.c.free(@ptrCast(@constCast(p)));
        if (results[i].symbology) |s| std.c.free(@ptrCast(@constCast(s)));
    }
    std.c.free(@ptrCast(results));
}

/// Free an array of ArUco results (frees each dictionary string, then the array).
export fn loupe_free_aruco_results(results: [*]LoupeArucoResult, count: u32) void {
    for (0..count) |i| {
        if (results[i].dictionary) |d| std.c.free(@ptrCast(@constCast(d)));
    }
    std.c.free(@ptrCast(results));
}
