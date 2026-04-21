const std = @import("std");
const builtin = @import("builtin");
const vision = @import("vision");

const version = "0.2.0";
const is_macos = builtin.os.tag == .macos;

fn printUsage(writer: *std.io.Writer) !void {
    try writer.print(
        \\Usage: loupe <command> [options] <image>
        \\
        \\Computer vision CLI powered by native OS APIs.
        \\Version {s} ({s})
        \\
    , .{ version, @tagName(builtin.os.tag) });

    // Cross-platform commands
    try writer.print(
        \\
        \\Commands:
        \\  faces      Detect faces in an image
        \\  ocr        Recognize text in an image
        \\  barcode    Scan barcodes in an image
        \\  qr         Scan QR codes in an image
        \\
    , .{});

    // macOS-only commands
    if (is_macos) {
        try writer.print(
            \\  landmarks  Detect facial landmarks (eyes, nose, mouth, etc.)
            \\  classify   Classify image content (scene/object labels)
            \\  body       Detect human body pose (skeleton joints)
            \\  hands      Detect hand pose (finger joints)
            \\  animals    Detect animals (cats, dogs)
            \\  rectangles Detect rectangular shapes
            \\  horizon    Measure horizon tilt angle
            \\  saliency   Find visually salient regions
            \\  score      Rate image aesthetic quality (macOS 15+)
            \\  segment    Generate person segmentation mask
            \\
        , .{});
    }

    try writer.print(
        \\  help       Show this help message
        \\
        \\Global options:
        \\  --json               Output results as JSON
        \\  --help, -h           Show this help message
        \\  --version, -V        Show version
        \\
        \\Options for 'faces':
        \\  -o <output>          Extract detected faces to files (or apply --blur/--redact)
        \\  --blur               Blur detected faces in output image
        \\  --redact             Redact (black box) detected faces in output image
        \\
    , .{});

    if (is_macos) {
        try writer.print(
            \\Options for 'segment':
            \\  -o <output.png>      Save segmentation mask as grayscale PNG
            \\
            \\Options for 'saliency':
            \\  --objects             Use objectness-based saliency (default: attention-based)
            \\
        , .{});
    }

    try writer.print(
        \\
        \\Created by George Mandis <george@mand.is>
        \\https://github.com/georgemandis/loupe
        \\
    , .{});
}

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

    // No arguments: print usage
    if (args.len < 2) {
        try printUsage(&stdout.interface);
        try stdout.interface.flush();
        return;
    }

    const subcommand = args[1];

    // Global --version / -V
    if (std.mem.eql(u8, subcommand, "--version") or std.mem.eql(u8, subcommand, "-V")) {
        try stdout.interface.print("loupe {s} ({s})\n", .{ version, @tagName(builtin.os.tag) });
        try stdout.interface.flush();
        return;
    }

    // Global --help / -h before subcommand dispatch
    if (std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "-h")) {
        try printUsage(&stdout.interface);
        try stdout.interface.flush();
        return;
    }

    if (std.mem.eql(u8, subcommand, "help")) {
        try printUsage(&stdout.interface);
        try stdout.interface.flush();
        return;
    }

    if (std.mem.eql(u8, subcommand, "faces")) {
        runFaces(allocator, args[2..], &stdout.interface, &stderr.interface);
        return; // runFaces calls process.exit, but guard against fall-through
    }

    if (std.mem.eql(u8, subcommand, "ocr")) {
        runOcr(allocator, args[2..], &stdout.interface, &stderr.interface);
        return;
    }

    if (std.mem.eql(u8, subcommand, "barcode") or std.mem.eql(u8, subcommand, "qr")) {
        const qr_only = std.mem.eql(u8, subcommand, "qr");
        runBarcode(allocator, args[2..], qr_only, &stdout.interface, &stderr.interface);
        return;
    }

    if (std.mem.eql(u8, subcommand, "classify")) {
        runSimple(allocator, args[2..], "classify", &stdout.interface, &stderr.interface);
        return;
    }

    if (std.mem.eql(u8, subcommand, "landmarks")) {
        runSimple(allocator, args[2..], "landmarks", &stdout.interface, &stderr.interface);
        return;
    }

    if (std.mem.eql(u8, subcommand, "body")) {
        runSimple(allocator, args[2..], "body", &stdout.interface, &stderr.interface);
        return;
    }

    if (std.mem.eql(u8, subcommand, "hands")) {
        runSimple(allocator, args[2..], "hands", &stdout.interface, &stderr.interface);
        return;
    }

    if (std.mem.eql(u8, subcommand, "animals")) {
        runSimple(allocator, args[2..], "animals", &stdout.interface, &stderr.interface);
        return;
    }

    if (std.mem.eql(u8, subcommand, "rectangles")) {
        runSimple(allocator, args[2..], "rectangles", &stdout.interface, &stderr.interface);
        return;
    }

    if (std.mem.eql(u8, subcommand, "horizon")) {
        runSimple(allocator, args[2..], "horizon", &stdout.interface, &stderr.interface);
        return;
    }

    if (std.mem.eql(u8, subcommand, "saliency")) {
        runSaliency(allocator, args[2..], &stdout.interface, &stderr.interface);
        return;
    }

    if (std.mem.eql(u8, subcommand, "score")) {
        runSimple(allocator, args[2..], "score", &stdout.interface, &stderr.interface);
        return;
    }

    if (std.mem.eql(u8, subcommand, "segment")) {
        runSegment(allocator, args[2..], &stdout.interface, &stderr.interface);
        return;
    }

    // Unknown subcommand
    try stderr.interface.print("Error: unknown command: {s}\n\n", .{subcommand});
    try printUsage(&stderr.interface);
    try stderr.interface.flush();
    std.process.exit(2);
}

// ---------------------------------------------------------------------------
// faces subcommand
// ---------------------------------------------------------------------------

fn runFaces(
    allocator: std.mem.Allocator,
    sub_args: []const []const u8,
    stdout_writer: *std.io.Writer,
    stderr_writer: *std.io.Writer,
) void {
    // Parse arguments
    var image_path: ?[]const u8 = null;
    var json_mode = false;
    var output_path: ?[]const u8 = null;
    var blur_mode: ?vision.BlurMode = null;

    var i: usize = 0;
    while (i < sub_args.len) : (i += 1) {
        const arg = sub_args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
        } else if (std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= sub_args.len) {
                stderr_writer.print("Error: -o requires an output path argument.\n", .{}) catch {};
                stderr_writer.flush() catch {};
                std.process.exit(2);
            }
            output_path = sub_args[i];
        } else if (std.mem.eql(u8, arg, "--blur")) {
            blur_mode = .blur;
        } else if (std.mem.eql(u8, arg, "--redact")) {
            blur_mode = .redact;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            stderr_writer.print("Error: unknown option: {s}\n", .{arg}) catch {};
            stderr_writer.flush() catch {};
            std.process.exit(2);
        } else {
            image_path = arg;
        }
    }

    // Validate: image path is required
    const path = image_path orelse {
        stderr_writer.print("Error: missing image path.\nUsage: loupe faces [options] <image>\n", .{}) catch {};
        stderr_writer.flush() catch {};
        std.process.exit(2);
    };

    // Validate: --blur/--redact requires -o
    if (blur_mode != null and output_path == null) {
        stderr_writer.print("Error: --blur/--redact requires -o <output>.\n", .{}) catch {};
        stderr_writer.flush() catch {};
        std.process.exit(2);
    }

    // Load image
    const handle = vision.loadImage(path) catch |err| {
        handleError(err, json_mode, stdout_writer, stderr_writer);
        return; // handleError calls process.exit
    };
    defer vision.freeImage(handle);

    // Detect faces
    const faces = vision.detectFaces(allocator, handle) catch |err| {
        handleError(err, json_mode, stdout_writer, stderr_writer);
        return;
    };
    defer allocator.free(faces);

    // Print results
    if (json_mode) {
        printFacesJson(stdout_writer, faces);
    } else {
        printFacesHuman(stdout_writer, faces);
    }
    stdout_writer.flush() catch {};

    // Output handling
    if (output_path) |out_path| {
        if (blur_mode) |mode| {
            // --blur or --redact: apply effect and save single image
            const blurred = vision.blurFaces(allocator, handle, faces, mode) catch |err| {
                handleError(err, json_mode, stdout_writer, stderr_writer);
                return;
            };
            defer vision.freeImage(blurred);

            vision.saveImage(blurred, out_path) catch |err| {
                handleError(err, json_mode, stdout_writer, stderr_writer);
                return;
            };
        } else {
            // -o without --blur/--redact: extract each face as a separate image
            extractFacesToFiles(allocator, handle, faces, out_path, stderr_writer);
        }
    }

    std.process.exit(0);
}

// ---------------------------------------------------------------------------
// Output helpers
// ---------------------------------------------------------------------------

fn printFacesHuman(writer: *std.io.Writer, faces: []const vision.FaceResult) void {
    if (faces.len == 0) {
        writer.print("No faces detected.\n", .{}) catch {};
        return;
    }
    writer.print("Found {d} face{s}:\n", .{ faces.len, if (faces.len == 1) "" else "s" }) catch {};
    for (faces, 0..) |face, idx| {
        writer.print("  Face {d}: ({d:.2}, {d:.2}) {d:.2}x{d:.2} [confidence: {d:.2}]\n", .{
            idx + 1,
            face.box.x,
            face.box.y,
            face.box.width,
            face.box.height,
            face.confidence,
        }) catch {};
    }
}

/// Extract each face to a numbered file: "output.png" → "output-1.png", "output-2.png", ...
/// If there's only one face, uses the path as-is.
fn extractFacesToFiles(
    allocator: std.mem.Allocator,
    image: vision.ImageHandle,
    faces: []const vision.FaceResult,
    out_path: []const u8,
    stderr_writer: *std.io.Writer,
) void {
    if (faces.len == 0) return;

    // Split "foo.png" into ("foo", ".png")
    const dot_pos = std.mem.lastIndexOfScalar(u8, out_path, '.') orelse out_path.len;
    const stem = out_path[0..dot_pos];
    const ext = out_path[dot_pos..];

    for (faces, 0..) |face, idx| {
        const cropped = vision.extractFace(image, face) catch |err| {
            stderr_writer.print("Error: failed to extract face {d}: {s}\n", .{ idx + 1, @errorName(err) }) catch {};
            stderr_writer.flush() catch {};
            continue;
        };
        defer vision.freeImage(cropped);

        // Build numbered path (or use as-is for single face)
        if (faces.len == 1) {
            vision.saveImage(cropped, out_path) catch |err| {
                stderr_writer.print("Error: failed to save face: {s}\n", .{@errorName(err)}) catch {};
                stderr_writer.flush() catch {};
            };
        } else {
            const numbered = std.fmt.allocPrint(allocator, "{s}-{d}{s}", .{ stem, idx + 1, ext }) catch {
                stderr_writer.print("Error: out of memory.\n", .{}) catch {};
                stderr_writer.flush() catch {};
                return;
            };
            defer allocator.free(numbered);
            vision.saveImage(cropped, numbered) catch |err| {
                stderr_writer.print("Error: failed to save face {d}: {s}\n", .{ idx + 1, @errorName(err) }) catch {};
                stderr_writer.flush() catch {};
            };
        }
    }
}

fn printFacesJson(writer: *std.io.Writer, faces: []const vision.FaceResult) void {
    writer.print("{{\"faces\":[", .{}) catch {};
    for (faces, 0..) |face, idx| {
        if (idx > 0) writer.print(",", .{}) catch {};
        writer.print("{{\"x\":{d:.2},\"y\":{d:.2},\"width\":{d:.2},\"height\":{d:.2},\"confidence\":{d:.2}}}", .{
            face.box.x,
            face.box.y,
            face.box.width,
            face.box.height,
            face.confidence,
        }) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

// ---------------------------------------------------------------------------
// ocr subcommand
// ---------------------------------------------------------------------------

fn runOcr(
    allocator: std.mem.Allocator,
    sub_args: []const []const u8,
    stdout_writer: *std.io.Writer,
    stderr_writer: *std.io.Writer,
) void {
    var image_path: ?[]const u8 = null;
    var json_mode = false;

    var i: usize = 0;
    while (i < sub_args.len) : (i += 1) {
        const arg = sub_args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            stderr_writer.print("Error: unknown option: {s}\n", .{arg}) catch {};
            stderr_writer.flush() catch {};
            std.process.exit(2);
        } else {
            image_path = arg;
        }
    }

    const path = image_path orelse {
        stderr_writer.print("Error: missing image path.\nUsage: loupe ocr [--json] <image>\n", .{}) catch {};
        stderr_writer.flush() catch {};
        std.process.exit(2);
    };

    const handle = vision.loadImage(path) catch |err| {
        handleError(err, json_mode, stdout_writer, stderr_writer);
        return;
    };
    defer vision.freeImage(handle);

    const results = vision.recognizeText(allocator, handle) catch |err| {
        handleError(err, json_mode, stdout_writer, stderr_writer);
        return;
    };
    defer vision.freeResults(allocator, vision.OcrResult, results);

    if (json_mode) {
        printOcrJson(stdout_writer, results);
    } else {
        printOcrHuman(stdout_writer, results);
    }
    stdout_writer.flush() catch {};

    std.process.exit(0);
}

fn printOcrHuman(writer: *std.io.Writer, results: []const vision.OcrResult) void {
    if (results.len == 0) {
        writer.print("No text detected.\n", .{}) catch {};
        return;
    }
    for (results) |r| {
        writer.print("{s}\n", .{r.text}) catch {};
    }
}

fn printOcrJson(writer: *std.io.Writer, results: []const vision.OcrResult) void {
    // Build combined text (all regions joined with newline)
    writer.print("{{\"text\":", .{}) catch {};
    if (results.len == 0) {
        writer.print("\"\"", .{}) catch {};
    } else {
        writer.print("\"", .{}) catch {};
        for (results, 0..) |r, idx| {
            if (idx > 0) writer.print("\\n", .{}) catch {};
            writeJsonString(writer, r.text);
        }
        writer.print("\"", .{}) catch {};
    }

    writer.print(",\"regions\":[", .{}) catch {};
    for (results, 0..) |r, idx| {
        if (idx > 0) writer.print(",", .{}) catch {};
        writer.print("{{\"text\":", .{}) catch {};
        writer.print("\"", .{}) catch {};
        writeJsonString(writer, r.text);
        writer.print("\"", .{}) catch {};
        writer.print(",\"x\":{d:.4},\"y\":{d:.4},\"width\":{d:.4},\"height\":{d:.4},\"confidence\":{d:.4}}}", .{
            r.box.x,
            r.box.y,
            r.box.width,
            r.box.height,
            r.confidence,
        }) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

// ---------------------------------------------------------------------------
// barcode / qr subcommand
// ---------------------------------------------------------------------------

fn runBarcode(
    allocator: std.mem.Allocator,
    sub_args: []const []const u8,
    qr_only: bool,
    stdout_writer: *std.io.Writer,
    stderr_writer: *std.io.Writer,
) void {
    var image_path: ?[]const u8 = null;
    var json_mode = false;

    var i: usize = 0;
    while (i < sub_args.len) : (i += 1) {
        const arg = sub_args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            stderr_writer.print("Error: unknown option: {s}\n", .{arg}) catch {};
            stderr_writer.flush() catch {};
            std.process.exit(2);
        } else {
            image_path = arg;
        }
    }

    const path = image_path orelse {
        const cmd = if (qr_only) "qr" else "barcode";
        stderr_writer.print("Error: missing image path.\nUsage: loupe {s} [--json] <image>\n", .{cmd}) catch {};
        stderr_writer.flush() catch {};
        std.process.exit(2);
    };

    const handle = vision.loadImage(path) catch |err| {
        handleError(err, json_mode, stdout_writer, stderr_writer);
        return;
    };
    defer vision.freeImage(handle);

    const results = vision.scanBarcodes(allocator, handle) catch |err| {
        handleError(err, json_mode, stdout_writer, stderr_writer);
        return;
    };
    defer vision.freeResults(allocator, vision.BarcodeResult, results);

    if (json_mode) {
        printBarcodesJson(stdout_writer, results, qr_only);
    } else {
        printBarcodesHuman(stdout_writer, results, qr_only);
    }
    stdout_writer.flush() catch {};

    std.process.exit(0);
}

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

fn printBarcodesHuman(writer: *std.io.Writer, results: []const vision.BarcodeResult, qr_only: bool) void {
    var printed: usize = 0;
    for (results) |r| {
        if (qr_only and r.symbology != .qr) continue;
        writer.print("{s}: {s}\n", .{ symbologyName(r.symbology), r.payload }) catch {};
        printed += 1;
    }
    if (printed == 0) {
        if (qr_only) {
            writer.print("No QR codes detected.\n", .{}) catch {};
        } else {
            writer.print("No barcodes detected.\n", .{}) catch {};
        }
    }
}

fn printBarcodesJson(writer: *std.io.Writer, results: []const vision.BarcodeResult, qr_only: bool) void {
    writer.print("{{\"barcodes\":[", .{}) catch {};
    var first = true;
    for (results) |r| {
        if (qr_only and r.symbology != .qr) continue;
        if (!first) writer.print(",", .{}) catch {};
        first = false;
        writer.print("{{\"payload\":\"", .{}) catch {};
        writeJsonString(writer, r.payload);
        writer.print("\",\"symbology\":\"{s}\",\"x\":{d:.4},\"y\":{d:.4},\"width\":{d:.4},\"height\":{d:.4}}}", .{
            @tagName(r.symbology),
            r.box.x,
            r.box.y,
            r.box.width,
            r.box.height,
        }) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

// ---------------------------------------------------------------------------
// Generic simple subcommand (--json + image path)
// ---------------------------------------------------------------------------

fn parseSimpleArgs(sub_args: []const []const u8, cmd: []const u8, stderr_writer: *std.io.Writer) struct { path: []const u8, json: bool } {
    var image_path: ?[]const u8 = null;
    var json_mode = false;

    for (sub_args) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            stderr_writer.print("Error: unknown option: {s}\n", .{arg}) catch {};
            stderr_writer.flush() catch {};
            std.process.exit(2);
        } else {
            image_path = arg;
        }
    }

    const path = image_path orelse {
        stderr_writer.print("Error: missing image path.\nUsage: loupe {s} [--json] <image>\n", .{cmd}) catch {};
        stderr_writer.flush() catch {};
        std.process.exit(2);
    };

    return .{ .path = path, .json = json_mode };
}

fn runSimple(
    allocator: std.mem.Allocator,
    sub_args: []const []const u8,
    cmd: []const u8,
    stdout_writer: *std.io.Writer,
    stderr_writer: *std.io.Writer,
) void {
    const parsed = parseSimpleArgs(sub_args, cmd, stderr_writer);

    const handle = vision.loadImage(parsed.path) catch |err| {
        handleError(err, parsed.json, stdout_writer, stderr_writer);
        return;
    };
    defer vision.freeImage(handle);

    if (std.mem.eql(u8, cmd, "classify")) {
        const results = vision.classifyImage(allocator, handle) catch |err| {
            handleError(err, parsed.json, stdout_writer, stderr_writer);
            return;
        };
        defer vision.freeResults(allocator, vision.ClassifyResult, results);
        if (parsed.json) printClassifyJson(stdout_writer, results) else printClassifyHuman(stdout_writer, results);
    } else if (std.mem.eql(u8, cmd, "landmarks")) {
        const results = vision.detectFaceLandmarks(allocator, handle) catch |err| {
            handleError(err, parsed.json, stdout_writer, stderr_writer);
            return;
        };
        defer vision.freeResults(allocator, vision.FaceLandmarksResult, results);
        if (parsed.json) printLandmarksJson(stdout_writer, results) else printLandmarksHuman(stdout_writer, results);
    } else if (std.mem.eql(u8, cmd, "body")) {
        const results = vision.detectBodyPose(allocator, handle) catch |err| {
            handleError(err, parsed.json, stdout_writer, stderr_writer);
            return;
        };
        defer vision.freeResults(allocator, vision.BodyPoseResult, results);
        if (parsed.json) printBodyJson(stdout_writer, results) else printBodyHuman(stdout_writer, results);
    } else if (std.mem.eql(u8, cmd, "hands")) {
        const results = vision.detectHandPose(allocator, handle) catch |err| {
            handleError(err, parsed.json, stdout_writer, stderr_writer);
            return;
        };
        defer vision.freeResults(allocator, vision.HandPoseResult, results);
        if (parsed.json) printHandsJson(stdout_writer, results) else printHandsHuman(stdout_writer, results);
    } else if (std.mem.eql(u8, cmd, "animals")) {
        const results = vision.recognizeAnimals(allocator, handle) catch |err| {
            handleError(err, parsed.json, stdout_writer, stderr_writer);
            return;
        };
        defer vision.freeResults(allocator, vision.AnimalResult, results);
        if (parsed.json) printAnimalsJson(stdout_writer, results) else printAnimalsHuman(stdout_writer, results);
    } else if (std.mem.eql(u8, cmd, "rectangles")) {
        const results = vision.detectRectangles(allocator, handle) catch |err| {
            handleError(err, parsed.json, stdout_writer, stderr_writer);
            return;
        };
        defer vision.freeResults(allocator, vision.RectangleResult, results);
        if (parsed.json) printRectanglesJson(stdout_writer, results) else printRectanglesHuman(stdout_writer, results);
    } else if (std.mem.eql(u8, cmd, "horizon")) {
        const result = vision.detectHorizon(handle) catch |err| {
            handleError(err, parsed.json, stdout_writer, stderr_writer);
            return;
        };
        if (parsed.json) {
            stdout_writer.print("{{\"angle\":{d:.4}}}\n", .{result.angle}) catch {};
        } else {
            stdout_writer.print("Horizon angle: {d:.2} degrees\n", .{result.angle}) catch {};
        }
    } else if (std.mem.eql(u8, cmd, "score")) {
        const result = vision.scoreAesthetics(handle) catch |err| {
            handleError(err, parsed.json, stdout_writer, stderr_writer);
            return;
        };
        if (parsed.json) {
            stdout_writer.print("{{\"score\":{d:.4},\"is_utility\":{s}}}\n", .{ result.score, if (result.is_utility) "true" else "false" }) catch {};
        } else {
            stdout_writer.print("Aesthetic score: {d:.2}\n", .{result.score}) catch {};
            if (result.is_utility) {
                stdout_writer.print("Type: utility image (screenshot, document, etc.)\n", .{}) catch {};
            } else {
                stdout_writer.print("Type: photographic image\n", .{}) catch {};
            }
        }
    }

    stdout_writer.flush() catch {};
    std.process.exit(0);
}

// ---------------------------------------------------------------------------
// saliency subcommand (has --objects flag)
// ---------------------------------------------------------------------------

fn runSaliency(
    allocator: std.mem.Allocator,
    sub_args: []const []const u8,
    stdout_writer: *std.io.Writer,
    stderr_writer: *std.io.Writer,
) void {
    var image_path: ?[]const u8 = null;
    var json_mode = false;
    var attention = true;

    for (sub_args) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
        } else if (std.mem.eql(u8, arg, "--objects")) {
            attention = false;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            stderr_writer.print("Error: unknown option: {s}\n", .{arg}) catch {};
            stderr_writer.flush() catch {};
            std.process.exit(2);
        } else {
            image_path = arg;
        }
    }

    const path = image_path orelse {
        stderr_writer.print("Error: missing image path.\nUsage: loupe saliency [--objects] [--json] <image>\n", .{}) catch {};
        stderr_writer.flush() catch {};
        std.process.exit(2);
    };

    const handle = vision.loadImage(path) catch |err| {
        handleError(err, json_mode, stdout_writer, stderr_writer);
        return;
    };
    defer vision.freeImage(handle);

    const results = vision.detectSaliency(allocator, handle, attention) catch |err| {
        handleError(err, json_mode, stdout_writer, stderr_writer);
        return;
    };
    defer vision.freeResults(allocator, vision.SaliencyRect, results);

    if (json_mode) printSaliencyJson(stdout_writer, results) else printSaliencyHuman(stdout_writer, results);
    stdout_writer.flush() catch {};
    std.process.exit(0);
}

// ---------------------------------------------------------------------------
// segment subcommand (has -o flag for mask output)
// ---------------------------------------------------------------------------

fn runSegment(
    allocator: std.mem.Allocator,
    sub_args: []const []const u8,
    stdout_writer: *std.io.Writer,
    stderr_writer: *std.io.Writer,
) void {
    var image_path: ?[]const u8 = null;
    var json_mode = false;
    var output_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < sub_args.len) : (i += 1) {
        const arg = sub_args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
        } else if (std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= sub_args.len) {
                stderr_writer.print("Error: -o requires an output path argument.\n", .{}) catch {};
                stderr_writer.flush() catch {};
                std.process.exit(2);
            }
            output_path = sub_args[i];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            stderr_writer.print("Error: unknown option: {s}\n", .{arg}) catch {};
            stderr_writer.flush() catch {};
            std.process.exit(2);
        } else {
            image_path = arg;
        }
    }

    const path = image_path orelse {
        stderr_writer.print("Error: missing image path.\nUsage: loupe segment [-o mask.png] [--json] <image>\n", .{}) catch {};
        stderr_writer.flush() catch {};
        std.process.exit(2);
    };

    const handle = vision.loadImage(path) catch |err| {
        handleError(err, json_mode, stdout_writer, stderr_writer);
        return;
    };
    defer vision.freeImage(handle);

    const seg = vision.segmentPerson(allocator, handle) catch |err| {
        handleError(err, json_mode, stdout_writer, stderr_writer);
        return;
    };
    defer vision.freeSegment(allocator, seg);

    if (json_mode) {
        stdout_writer.print("{{\"width\":{d},\"height\":{d},\"has_person\":{s}}}\n", .{
            seg.width,
            seg.height,
            if (hasPerson(seg)) "true" else "false",
        }) catch {};
    } else {
        stdout_writer.print("Segmentation mask: {d}x{d}\n", .{ seg.width, seg.height }) catch {};
        if (hasPerson(seg)) {
            stdout_writer.print("Person detected in image.\n", .{}) catch {};
        } else {
            stdout_writer.print("No person detected.\n", .{}) catch {};
        }
    }
    stdout_writer.flush() catch {};

    // Save mask as grayscale PNG if -o provided
    if (output_path) |out_path| {
        saveMaskAsPng(seg, out_path, stderr_writer);
    }

    std.process.exit(0);
}

fn hasPerson(seg: vision.SegmentResult) bool {
    for (seg.mask_data) |b| {
        if (b > 128) return true;
    }
    return false;
}

fn saveMaskAsPng(seg: vision.SegmentResult, path: []const u8, stderr_writer: *std.io.Writer) void {
    // Create a grayscale CGImage from the mask data and save it
    // We need to go through CoreGraphics to write a PNG
    // For simplicity, use the vision layer — create a CGImage from raw grayscale data
    _ = seg;
    _ = path;
    stderr_writer.print("Note: mask PNG output not yet implemented. Use --json to get mask dimensions.\n", .{}) catch {};
    stderr_writer.flush() catch {};
}

// ---------------------------------------------------------------------------
// Print functions for new commands
// ---------------------------------------------------------------------------

fn printClassifyHuman(writer: *std.io.Writer, results: []const vision.ClassifyResult) void {
    if (results.len == 0) {
        writer.print("No classifications.\n", .{}) catch {};
        return;
    }
    for (results) |r| {
        writer.print("{s}: {d:.2}\n", .{ r.label, r.confidence }) catch {};
    }
}

fn printClassifyJson(writer: *std.io.Writer, results: []const vision.ClassifyResult) void {
    writer.print("{{\"labels\":[", .{}) catch {};
    for (results, 0..) |r, idx| {
        if (idx > 0) writer.print(",", .{}) catch {};
        writer.print("{{\"label\":\"", .{}) catch {};
        writeJsonString(writer, r.label);
        writer.print("\",\"confidence\":{d:.4}}}", .{r.confidence}) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

fn printLandmarksHuman(writer: *std.io.Writer, results: []const vision.FaceLandmarksResult) void {
    if (results.len == 0) {
        writer.print("No faces detected.\n", .{}) catch {};
        return;
    }
    writer.print("Found {d} face{s} with landmarks:\n", .{ results.len, if (results.len == 1) "" else "s" }) catch {};
    for (results, 0..) |r, idx| {
        writer.print("  Face {d}: ({d:.2}, {d:.2}) {d:.2}x{d:.2}\n", .{ idx + 1, r.box.x, r.box.y, r.box.width, r.box.height }) catch {};
        writer.print("    left eye: {d} pts, right eye: {d} pts, nose: {d} pts\n", .{ r.left_eye.len, r.right_eye.len, r.nose.len }) catch {};
        writer.print("    lips: {d} pts, contour: {d} pts\n", .{ r.outer_lips.len, r.face_contour.len }) catch {};
    }
}

fn printLandmarksJson(writer: *std.io.Writer, results: []const vision.FaceLandmarksResult) void {
    writer.print("{{\"faces\":[", .{}) catch {};
    for (results, 0..) |r, idx| {
        if (idx > 0) writer.print(",", .{}) catch {};
        writer.print("{{\"x\":{d:.4},\"y\":{d:.4},\"width\":{d:.4},\"height\":{d:.4},\"confidence\":{d:.4}", .{
            r.box.x, r.box.y, r.box.width, r.box.height, r.confidence,
        }) catch {};
        printPointsJson(writer, "left_eye", r.left_eye);
        printPointsJson(writer, "right_eye", r.right_eye);
        printPointsJson(writer, "nose", r.nose);
        printPointsJson(writer, "outer_lips", r.outer_lips);
        printPointsJson(writer, "left_eyebrow", r.left_eyebrow);
        printPointsJson(writer, "right_eyebrow", r.right_eyebrow);
        printPointsJson(writer, "face_contour", r.face_contour);
        writer.print("}}", .{}) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

fn printPointsJson(writer: *std.io.Writer, name: []const u8, points: []const vision.LandmarkPoint) void {
    writer.print(",\"{s}\":[", .{name}) catch {};
    for (points, 0..) |p, j| {
        if (j > 0) writer.print(",", .{}) catch {};
        writer.print("[{d:.4},{d:.4}]", .{ p.x, p.y }) catch {};
    }
    writer.print("]", .{}) catch {};
}

fn printBodyHuman(writer: *std.io.Writer, results: []const vision.BodyPoseResult) void {
    if (results.len == 0) {
        writer.print("No bodies detected.\n", .{}) catch {};
        return;
    }
    writer.print("Found {d} body pose{s}:\n", .{ results.len, if (results.len == 1) "" else "s" }) catch {};
    for (results, 0..) |r, idx| {
        writer.print("  Body {d}: {d} joints\n", .{ idx + 1, r.joints.len }) catch {};
        for (r.joints) |j| {
            writer.print("    {s}: ({d:.3}, {d:.3}) [{d:.2}]\n", .{ j.name, j.x, j.y, j.confidence }) catch {};
        }
    }
}

fn printBodyJson(writer: *std.io.Writer, results: []const vision.BodyPoseResult) void {
    writer.print("{{\"bodies\":[", .{}) catch {};
    for (results, 0..) |r, idx| {
        if (idx > 0) writer.print(",", .{}) catch {};
        writer.print("{{\"joints\":[", .{}) catch {};
        for (r.joints, 0..) |j, ji| {
            if (ji > 0) writer.print(",", .{}) catch {};
            writer.print("{{\"name\":\"", .{}) catch {};
            writeJsonString(writer, j.name);
            writer.print("\",\"x\":{d:.4},\"y\":{d:.4},\"confidence\":{d:.4}}}", .{ j.x, j.y, j.confidence }) catch {};
        }
        writer.print("]}}", .{}) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

fn printHandsHuman(writer: *std.io.Writer, results: []const vision.HandPoseResult) void {
    if (results.len == 0) {
        writer.print("No hands detected.\n", .{}) catch {};
        return;
    }
    writer.print("Found {d} hand{s}:\n", .{ results.len, if (results.len == 1) "" else "s" }) catch {};
    for (results, 0..) |r, idx| {
        writer.print("  Hand {d} ({s}): {d} joints\n", .{ idx + 1, r.chirality, r.joints.len }) catch {};
        for (r.joints) |j| {
            writer.print("    {s}: ({d:.3}, {d:.3}) [{d:.2}]\n", .{ j.name, j.x, j.y, j.confidence }) catch {};
        }
    }
}

fn printHandsJson(writer: *std.io.Writer, results: []const vision.HandPoseResult) void {
    writer.print("{{\"hands\":[", .{}) catch {};
    for (results, 0..) |r, idx| {
        if (idx > 0) writer.print(",", .{}) catch {};
        writer.print("{{\"chirality\":\"", .{}) catch {};
        writeJsonString(writer, r.chirality);
        writer.print("\",\"joints\":[", .{}) catch {};
        for (r.joints, 0..) |j, ji| {
            if (ji > 0) writer.print(",", .{}) catch {};
            writer.print("{{\"name\":\"", .{}) catch {};
            writeJsonString(writer, j.name);
            writer.print("\",\"x\":{d:.4},\"y\":{d:.4},\"confidence\":{d:.4}}}", .{ j.x, j.y, j.confidence }) catch {};
        }
        writer.print("]}}", .{}) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

fn printAnimalsHuman(writer: *std.io.Writer, results: []const vision.AnimalResult) void {
    if (results.len == 0) {
        writer.print("No animals detected.\n", .{}) catch {};
        return;
    }
    for (results, 0..) |r, idx| {
        writer.print("  Animal {d}: {s} ({d:.2}, {d:.2}) {d:.2}x{d:.2} [confidence: {d:.2}]\n", .{
            idx + 1, r.label, r.box.x, r.box.y, r.box.width, r.box.height, r.confidence,
        }) catch {};
    }
}

fn printAnimalsJson(writer: *std.io.Writer, results: []const vision.AnimalResult) void {
    writer.print("{{\"animals\":[", .{}) catch {};
    for (results, 0..) |r, idx| {
        if (idx > 0) writer.print(",", .{}) catch {};
        writer.print("{{\"label\":\"", .{}) catch {};
        writeJsonString(writer, r.label);
        writer.print("\",\"confidence\":{d:.4},\"x\":{d:.4},\"y\":{d:.4},\"width\":{d:.4},\"height\":{d:.4}}}", .{
            r.confidence, r.box.x, r.box.y, r.box.width, r.box.height,
        }) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

fn printRectanglesHuman(writer: *std.io.Writer, results: []const vision.RectangleResult) void {
    if (results.len == 0) {
        writer.print("No rectangles detected.\n", .{}) catch {};
        return;
    }
    writer.print("Found {d} rectangle{s}:\n", .{ results.len, if (results.len == 1) "" else "s" }) catch {};
    for (results, 0..) |r, idx| {
        writer.print("  Rectangle {d}:\n", .{idx + 1}) catch {};
        writer.print("    top-left: ({d:.3}, {d:.3})  top-right: ({d:.3}, {d:.3})\n", .{ r.top_left.x, r.top_left.y, r.top_right.x, r.top_right.y }) catch {};
        writer.print("    bottom-left: ({d:.3}, {d:.3})  bottom-right: ({d:.3}, {d:.3})\n", .{ r.bottom_left.x, r.bottom_left.y, r.bottom_right.x, r.bottom_right.y }) catch {};
    }
}

fn printRectanglesJson(writer: *std.io.Writer, results: []const vision.RectangleResult) void {
    writer.print("{{\"rectangles\":[", .{}) catch {};
    for (results, 0..) |r, idx| {
        if (idx > 0) writer.print(",", .{}) catch {};
        writer.print("{{\"top_left\":[{d:.4},{d:.4}],\"top_right\":[{d:.4},{d:.4}],\"bottom_left\":[{d:.4},{d:.4}],\"bottom_right\":[{d:.4},{d:.4}]}}", .{
            r.top_left.x,  r.top_left.y,
            r.top_right.x, r.top_right.y,
            r.bottom_left.x,  r.bottom_left.y,
            r.bottom_right.x, r.bottom_right.y,
        }) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

fn printSaliencyHuman(writer: *std.io.Writer, results: []const vision.SaliencyRect) void {
    if (results.len == 0) {
        writer.print("No salient regions detected.\n", .{}) catch {};
        return;
    }
    writer.print("Found {d} salient region{s}:\n", .{ results.len, if (results.len == 1) "" else "s" }) catch {};
    for (results, 0..) |r, idx| {
        writer.print("  Region {d}: ({d:.3}, {d:.3}) {d:.3}x{d:.3}\n", .{ idx + 1, r.box.x, r.box.y, r.box.width, r.box.height }) catch {};
    }
}

fn printSaliencyJson(writer: *std.io.Writer, results: []const vision.SaliencyRect) void {
    writer.print("{{\"regions\":[", .{}) catch {};
    for (results, 0..) |r, idx| {
        if (idx > 0) writer.print(",", .{}) catch {};
        writer.print("{{\"x\":{d:.4},\"y\":{d:.4},\"width\":{d:.4},\"height\":{d:.4}}}", .{
            r.box.x, r.box.y, r.box.width, r.box.height,
        }) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

/// Write a JSON-escaped string value (without surrounding quotes).
fn writeJsonString(writer: *std.io.Writer, s: []const u8) void {
    for (s) |c| {
        switch (c) {
            '"' => writer.print("\\\"", .{}) catch {},
            '\\' => writer.print("\\\\", .{}) catch {},
            '\n' => writer.print("\\n", .{}) catch {},
            '\r' => writer.print("\\r", .{}) catch {},
            '\t' => writer.print("\\t", .{}) catch {},
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => writer.print("\\u{X:0>4}", .{c}) catch {},
            else => writer.print("{c}", .{c}) catch {},
        }
    }
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
            error.DetectionFailed => "detection_failed",
            error.SaveFailed => "save_failed",
            error.UnsupportedFormat => "unsupported_format",
            error.UnsupportedPlatform => "unsupported_platform",
            else => "unknown_error",
        };
        stdout_writer.print("{{\"error\":\"{s}\"}}\n", .{error_key}) catch {};
        stdout_writer.flush() catch {};
    }
    // Human-readable error on stderr
    switch (err) {
        error.ImageLoadFailed => stderr_writer.print("Error: failed to load image.\n", .{}) catch {},
        error.DetectionFailed => stderr_writer.print("Error: detection failed.\n", .{}) catch {},
        error.SaveFailed => stderr_writer.print("Error: failed to save image.\n", .{}) catch {},
        error.UnsupportedFormat => stderr_writer.print("Error: unsupported image format.\n", .{}) catch {},
        error.UnsupportedPlatform => stderr_writer.print("Error: unsupported platform.\n", .{}) catch {},
        error.OutOfMemory => stderr_writer.print("Error: out of memory.\n", .{}) catch {},
        else => stderr_writer.print("Error: unexpected error ({s})\n", .{@errorName(err)}) catch {},
    }
    stderr_writer.flush() catch {};
    std.process.exit(1);
}
