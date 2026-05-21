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
