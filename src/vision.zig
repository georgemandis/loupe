const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const platform = switch (builtin.os.tag) {
    .macos => @import("platform/macos.zig"),
    .windows => @import("platform/windows.zig"),
    else => @compileError("Unsupported platform. Currently supported: macOS, Windows."),
};

pub const aruco = @import("aruco.zig");

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

pub const ClassifyResult = struct {
    label: []const u8,
    confidence: f64,
};

pub const LandmarkPoint = struct {
    x: f64,
    y: f64,
};

pub const FaceLandmarksResult = struct {
    box: BoundingBox,
    confidence: f64,
    left_eye: []const LandmarkPoint,
    right_eye: []const LandmarkPoint,
    nose: []const LandmarkPoint,
    outer_lips: []const LandmarkPoint,
    left_eyebrow: []const LandmarkPoint,
    right_eyebrow: []const LandmarkPoint,
    face_contour: []const LandmarkPoint,
};

pub const JointPoint = struct {
    name: []const u8,
    x: f64,
    y: f64,
    confidence: f64,
};

pub const BodyPoseResult = struct {
    joints: []const JointPoint,
};

pub const HandPoseResult = struct {
    chirality: []const u8, // "left", "right", or "unknown"
    joints: []const JointPoint,
};

pub const SaliencyRect = struct {
    box: BoundingBox,
};

pub const HorizonResult = struct {
    angle: f64,
};

pub const AnimalResult = struct {
    label: []const u8,
    confidence: f64,
    box: BoundingBox,
};

pub const RectangleResult = struct {
    top_left: LandmarkPoint,
    top_right: LandmarkPoint,
    bottom_left: LandmarkPoint,
    bottom_right: LandmarkPoint,
    box: BoundingBox,
};

pub const AestheticsResult = struct {
    score: f64,
    is_utility: bool,
};

pub const SegmentResult = struct {
    width: usize,
    height: usize,
    mask_data: []const u8,
};

/// Grayscale pixel buffer, row-major, one byte per pixel, row 0 = top.
pub const GrayPixels = struct {
    width: usize,
    height: usize,
    pixels: []u8,
};

/// Result of ArUco marker detection. The `dictionary` field is a static string
/// (e.g. "DICT_4X4_50") and is never freed; freeResults handles this via the
/// else => {} branch.
pub const ArucoResult = struct {
    id: u32,
    grid: u8, // marker grid size: 4, 5, 6, or 7
    dictionary: []const u8, // static string (e.g. "DICT_4X4_50") — never freed
    /// Normalized coordinates, top-left origin, canonical marker order
    /// (corner 0 = marker's top-left), clockwise.
    corners: [4]LandmarkPoint,
    box: BoundingBox,
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

pub fn loadImage(path: []const u8) VisionError!ImageHandle {
    return platform.loadImage(path);
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

pub fn extractFace(image: ImageHandle, face: FaceResult) VisionError!ImageHandle {
    return platform.extractFace(image, face);
}

pub fn blurFaces(allocator: Allocator, image: ImageHandle, faces: []const FaceResult, mode: BlurMode) VisionError!ImageHandle {
    return platform.blurFaces(allocator, image, faces, mode);
}

pub fn classifyImage(allocator: Allocator, image: ImageHandle) VisionError![]ClassifyResult {
    return platform.classifyImage(allocator, image);
}

pub fn detectFaceLandmarks(allocator: Allocator, image: ImageHandle) VisionError![]FaceLandmarksResult {
    return platform.detectFaceLandmarks(allocator, image);
}

pub fn detectBodyPose(allocator: Allocator, image: ImageHandle) VisionError![]BodyPoseResult {
    return platform.detectBodyPose(allocator, image);
}

pub fn detectHandPose(allocator: Allocator, image: ImageHandle) VisionError![]HandPoseResult {
    return platform.detectHandPose(allocator, image);
}

pub fn detectSaliency(allocator: Allocator, image: ImageHandle, attention: bool) VisionError![]SaliencyRect {
    return platform.detectSaliency(allocator, image, attention);
}

pub fn detectHorizon(image: ImageHandle) VisionError!HorizonResult {
    return platform.detectHorizon(image);
}

pub fn recognizeAnimals(allocator: Allocator, image: ImageHandle) VisionError![]AnimalResult {
    return platform.recognizeAnimals(allocator, image);
}

pub fn detectRectangles(allocator: Allocator, image: ImageHandle) VisionError![]RectangleResult {
    return platform.detectRectangles(allocator, image);
}

pub fn detectAruco(allocator: Allocator, image: ImageHandle, opts: aruco.Options) VisionError![]ArucoResult {
    const candidates = try platform.detectArucoCandidates(allocator, image);
    defer allocator.free(candidates);

    // Skip the full-resolution grayscale render when there is nothing to decode.
    if (candidates.len == 0) {
        return allocator.alloc(ArucoResult, 0) catch return VisionError.OutOfMemory;
    }

    const gray = try platform.getGrayscalePixels(allocator, image);
    defer allocator.free(gray.pixels);

    const img = aruco.GrayImage{ .width = gray.width, .height = gray.height, .pixels = gray.pixels };
    const w: f64 = @floatFromInt(gray.width);
    const h: f64 = @floatFromInt(gray.height);

    var results: std.ArrayList(ArucoResult) = .empty;
    defer results.deinit(allocator);

    for (candidates) |cand| {
        const quad = aruco.Quad{
            .top_left = .{ .x = cand.top_left.x * w, .y = cand.top_left.y * h },
            .top_right = .{ .x = cand.top_right.x * w, .y = cand.top_right.y * h },
            .bottom_right = .{ .x = cand.bottom_right.x * w, .y = cand.bottom_right.y * h },
            .bottom_left = .{ .x = cand.bottom_left.x * w, .y = cand.bottom_left.y * h },
        };
        const decoded = aruco.decodeQuad(img, quad, opts) orelse continue;

        var corners: [4]LandmarkPoint = undefined;
        // Vision can return normalized coordinates slightly outside [0, 1] for
        // near-edge quads, so the extrema must start at infinity.
        var min_x = std.math.inf(f64);
        var min_y = std.math.inf(f64);
        var max_x = -std.math.inf(f64);
        var max_y = -std.math.inf(f64);
        for (decoded.corners, 0..) |p, i| {
            const nx = p.x / w;
            const ny = p.y / h;
            corners[i] = .{ .x = nx, .y = ny };
            min_x = @min(min_x, nx);
            min_y = @min(min_y, ny);
            max_x = @max(max_x, nx);
            max_y = @max(max_y, ny);
        }

        const new = ArucoResult{
            .id = decoded.id,
            .grid = decoded.n,
            .dictionary = aruco.canonicalName(decoded.n, decoded.id),
            .corners = corners,
            .box = .{ .x = min_x, .y = min_y, .width = max_x - min_x, .height = max_y - min_y },
        };

        // Vision sometimes reports near-identical quads for one marker.
        const cx = min_x + (max_x - min_x) / 2.0;
        const cy = min_y + (max_y - min_y) / 2.0;
        var dup = false;
        for (results.items) |r| {
            const rcx = r.box.x + r.box.width / 2.0;
            const rcy = r.box.y + r.box.height / 2.0;
            if (r.id == new.id and r.grid == new.grid and
                @abs(rcx - cx) < 0.02 and @abs(rcy - cy) < 0.02)
            {
                dup = true;
                break;
            }
        }
        if (!dup) results.append(allocator, new) catch return VisionError.OutOfMemory;
    }

    return results.toOwnedSlice(allocator) catch return VisionError.OutOfMemory;
}

pub fn scoreAesthetics(image: ImageHandle) VisionError!AestheticsResult {
    return platform.scoreAesthetics(image);
}

pub fn segmentPerson(allocator: Allocator, image: ImageHandle) VisionError!SegmentResult {
    return platform.segmentPerson(allocator, image);
}

pub fn saveMaskAsPng(seg: SegmentResult, path: []const u8, source_image: ImageHandle) VisionError!void {
    return platform.saveMaskAsPng(seg, path, source_image);
}

pub fn saveImage(image: ImageHandle, path: []const u8) VisionError!void {
    return platform.saveImage(image, path);
}

pub fn freeImage(image: ImageHandle) void {
    platform.freeImage(image);
}

pub fn freeResults(allocator: Allocator, comptime T: type, results: []T) void {
    for (results) |*r| {
        switch (T) {
            // dictionary is a static string; nothing to free per item.
            ArucoResult => {},
            OcrResult => allocator.free(r.text),
            BarcodeResult => allocator.free(r.payload),
            ClassifyResult => allocator.free(r.label),
            AnimalResult => allocator.free(r.label),
            FaceLandmarksResult => {
                allocator.free(r.left_eye);
                allocator.free(r.right_eye);
                allocator.free(r.nose);
                allocator.free(r.outer_lips);
                allocator.free(r.left_eyebrow);
                allocator.free(r.right_eyebrow);
                allocator.free(r.face_contour);
            },
            BodyPoseResult => {
                for (r.joints) |j| allocator.free(j.name);
                allocator.free(r.joints);
            },
            HandPoseResult => {
                allocator.free(r.chirality);
                for (r.joints) |j| allocator.free(j.name);
                allocator.free(r.joints);
            },
            else => {},
        }
    }
    allocator.free(results);
}

pub fn freeSegment(allocator: Allocator, seg: SegmentResult) void {
    allocator.free(seg.mask_data);
}
