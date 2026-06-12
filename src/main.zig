const std = @import("std");
const builtin = @import("builtin");
const vision = @import("vision");

const version = "0.3.1";
const is_macos = builtin.os.tag == .macos;

fn printUsage(writer: *std.Io.Writer) !void {
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
            \\  aruco      Detect ArUco fiducial markers
            \\
        , .{});
    }

    try writer.print(
        \\  completions Print shell completions (fish, bash, zsh)
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
            \\Options for 'aruco':
            \\  --dict <name>        Restrict to one dictionary (e.g. 4X4_50, 6X6_250)
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

pub fn main(init: std.process.Init) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buf);

    var stderr_buf: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(init.io, &stderr_buf);

    const allocator = init.gpa;

    // Collect args into a slice for indexed access
    var args_list: std.ArrayList([:0]const u8) = .empty;
    defer args_list.deinit(allocator);
    var args_iter = try std.process.Args.iterateAllocator(init.minimal.args, allocator);
    defer args_iter.deinit();
    while (args_iter.next()) |arg| {
        try args_list.append(allocator, arg);
    }
    const args = args_list.items;

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

    if (std.mem.eql(u8, subcommand, "completions")) {
        runCompletions(args[2..], &stdout.interface, &stderr.interface);
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

    if (std.mem.eql(u8, subcommand, "aruco")) {
        runAruco(allocator, args[2..], &stdout.interface, &stderr.interface);
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
    stdout_writer: *std.Io.Writer,
    stderr_writer: *std.Io.Writer,
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

fn printFacesHuman(writer: *std.Io.Writer, faces: []const vision.FaceResult) void {
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
    stderr_writer: *std.Io.Writer,
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

fn printFacesJson(writer: *std.Io.Writer, faces: []const vision.FaceResult) void {
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
    stdout_writer: *std.Io.Writer,
    stderr_writer: *std.Io.Writer,
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

fn printOcrHuman(writer: *std.Io.Writer, results: []const vision.OcrResult) void {
    if (results.len == 0) {
        writer.print("No text detected.\n", .{}) catch {};
        return;
    }
    for (results) |r| {
        writer.print("{s}\n", .{r.text}) catch {};
    }
}

fn printOcrJson(writer: *std.Io.Writer, results: []const vision.OcrResult) void {
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
    stdout_writer: *std.Io.Writer,
    stderr_writer: *std.Io.Writer,
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

fn printBarcodesHuman(writer: *std.Io.Writer, results: []const vision.BarcodeResult, qr_only: bool) void {
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

fn printBarcodesJson(writer: *std.Io.Writer, results: []const vision.BarcodeResult, qr_only: bool) void {
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

fn parseSimpleArgs(sub_args: []const []const u8, cmd: []const u8, stderr_writer: *std.Io.Writer) struct { path: []const u8, json: bool } {
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
    stdout_writer: *std.Io.Writer,
    stderr_writer: *std.Io.Writer,
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
    stdout_writer: *std.Io.Writer,
    stderr_writer: *std.Io.Writer,
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
    stdout_writer: *std.Io.Writer,
    stderr_writer: *std.Io.Writer,
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
        saveMaskAsPng(seg, out_path, handle, stderr_writer);
    }

    std.process.exit(0);
}

fn hasPerson(seg: vision.SegmentResult) bool {
    for (seg.mask_data) |b| {
        if (b > 128) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// aruco subcommand (has --dict flag)
// ---------------------------------------------------------------------------

fn runAruco(
    allocator: std.mem.Allocator,
    sub_args: []const []const u8,
    stdout_writer: *std.Io.Writer,
    stderr_writer: *std.Io.Writer,
) void {
    var image_path: ?[]const u8 = null;
    var json_mode = false;
    var spec: ?vision.aruco.DictSpec = null;

    var i: usize = 0;
    while (i < sub_args.len) : (i += 1) {
        const arg = sub_args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            json_mode = true;
        } else if (std.mem.eql(u8, arg, "--dict")) {
            i += 1;
            if (i >= sub_args.len) {
                stderr_writer.print("Error: --dict requires a dictionary name.\n", .{}) catch {};
                stderr_writer.flush() catch {};
                std.process.exit(2);
            }
            spec = vision.aruco.dictByName(sub_args[i]) orelse {
                stderr_writer.print("Error: unknown dictionary: {s}\nValid dictionaries (case-insensitive, DICT_ prefix optional): {s}\n", .{ sub_args[i], vision.aruco.dict_names_help }) catch {};
                stderr_writer.flush() catch {};
                std.process.exit(2);
            };
        } else if (std.mem.startsWith(u8, arg, "-")) {
            stderr_writer.print("Error: unknown option: {s}\n", .{arg}) catch {};
            stderr_writer.flush() catch {};
            std.process.exit(2);
        } else {
            image_path = arg;
        }
    }

    const path = image_path orelse {
        stderr_writer.print("Error: missing image path.\nUsage: loupe aruco [--dict <name>] [--json] <image>\n", .{}) catch {};
        stderr_writer.flush() catch {};
        std.process.exit(2);
    };

    const handle = vision.loadImage(path) catch |err| {
        handleError(err, json_mode, stdout_writer, stderr_writer);
        return;
    };
    defer vision.freeImage(handle);

    const results = vision.detectAruco(allocator, handle, .{ .spec = spec }) catch |err| {
        handleError(err, json_mode, stdout_writer, stderr_writer);
        return;
    };
    defer vision.freeResults(allocator, vision.ArucoResult, results);

    if (json_mode) printArucoJson(stdout_writer, results) else printArucoHuman(stdout_writer, results);
    stdout_writer.flush() catch {};
    std.process.exit(0);
}

fn printArucoHuman(writer: *std.Io.Writer, results: []const vision.ArucoResult) void {
    if (results.len == 0) {
        writer.print("No markers detected.\n", .{}) catch {};
        return;
    }
    writer.print("Found {d} marker{s}:\n", .{ results.len, if (results.len == 1) "" else "s" }) catch {};
    for (results, 0..) |r, idx| {
        writer.print("  Marker {d}: id {d} ({s})\n", .{ idx + 1, r.id, r.dictionary }) catch {};
        writer.print("    top-left: ({d:.3}, {d:.3})  top-right: ({d:.3}, {d:.3})\n", .{ r.corners[0].x, r.corners[0].y, r.corners[1].x, r.corners[1].y }) catch {};
        writer.print("    bottom-right: ({d:.3}, {d:.3})  bottom-left: ({d:.3}, {d:.3})\n", .{ r.corners[2].x, r.corners[2].y, r.corners[3].x, r.corners[3].y }) catch {};
    }
}

fn printArucoJson(writer: *std.Io.Writer, results: []const vision.ArucoResult) void {
    writer.print("{{\"markers\":[", .{}) catch {};
    for (results, 0..) |r, idx| {
        if (idx > 0) writer.print(",", .{}) catch {};
        writer.print("{{\"id\":{d},\"dictionary\":\"{s}\",\"corners\":[", .{ r.id, r.dictionary }) catch {};
        for (r.corners, 0..) |p, j| {
            if (j > 0) writer.print(",", .{}) catch {};
            writer.print("[{d:.4},{d:.4}]", .{ p.x, p.y }) catch {};
        }
        writer.print("],\"x\":{d:.4},\"y\":{d:.4},\"width\":{d:.4},\"height\":{d:.4}}}", .{
            r.box.x, r.box.y, r.box.width, r.box.height,
        }) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

// ---------------------------------------------------------------------------
// completions subcommand
// ---------------------------------------------------------------------------

fn runCompletions(
    sub_args: []const []const u8,
    stdout_writer: *std.Io.Writer,
    stderr_writer: *std.Io.Writer,
) void {
    const shell = if (sub_args.len > 0) sub_args[0] else {
        stderr_writer.print("Usage: loupe completions <fish|bash|zsh>\n", .{}) catch {};
        stderr_writer.flush() catch {};
        std.process.exit(1);
    };

    const output = if (std.mem.eql(u8, shell, "fish"))
        fish_completions
    else if (std.mem.eql(u8, shell, "bash"))
        bash_completions
    else if (std.mem.eql(u8, shell, "zsh"))
        zsh_completions
    else {
        stderr_writer.print("Unknown shell: {s}. Supported: fish, bash, zsh\n", .{shell}) catch {};
        stderr_writer.flush() catch {};
        std.process.exit(1);
    };

    stdout_writer.print("{s}", .{output}) catch {};
    stdout_writer.flush() catch {};
    std.process.exit(0);
}

const fish_completions =
    \\# loupe completions for fish
    \\# Install: loupe completions fish | source
    \\# Persist: loupe completions fish > ~/.config/fish/completions/loupe.fish
    \\
    \\complete -e -c loupe
    \\complete -c loupe -f
    \\complete -c loupe -n "__fish_use_subcommand" -a "faces" -d "Detect faces in an image"
    \\complete -c loupe -n "__fish_use_subcommand" -a "ocr" -d "Recognize text in an image"
    \\complete -c loupe -n "__fish_use_subcommand" -a "barcode" -d "Scan barcodes in an image"
    \\complete -c loupe -n "__fish_use_subcommand" -a "qr" -d "Scan QR codes in an image"
    \\complete -c loupe -n "__fish_use_subcommand" -a "landmarks" -d "Detect facial landmarks"
    \\complete -c loupe -n "__fish_use_subcommand" -a "classify" -d "Classify image content"
    \\complete -c loupe -n "__fish_use_subcommand" -a "body" -d "Detect human body pose"
    \\complete -c loupe -n "__fish_use_subcommand" -a "hands" -d "Detect hand pose"
    \\complete -c loupe -n "__fish_use_subcommand" -a "animals" -d "Detect animals"
    \\complete -c loupe -n "__fish_use_subcommand" -a "rectangles" -d "Detect rectangular shapes"
    \\complete -c loupe -n "__fish_use_subcommand" -a "horizon" -d "Measure horizon tilt angle"
    \\complete -c loupe -n "__fish_use_subcommand" -a "saliency" -d "Find visually salient regions"
    \\complete -c loupe -n "__fish_use_subcommand" -a "score" -d "Rate image aesthetic quality"
    \\complete -c loupe -n "__fish_use_subcommand" -a "segment" -d "Generate person segmentation mask"
    \\complete -c loupe -n "__fish_use_subcommand" -a "aruco" -d "Detect ArUco markers"
    \\complete -c loupe -n "__fish_use_subcommand" -a "completions" -d "Print shell completions"
    \\complete -c loupe -n "__fish_use_subcommand" -a "help" -d "Show help"
    \\complete -c loupe -l json -d "Output as JSON"
    \\complete -c loupe -l help -s h -d "Show help"
    \\complete -c loupe -l version -s V -d "Show version"
    \\
    \\# faces options
    \\complete -c loupe -n "__fish_seen_subcommand_from faces" -s o -r -d "Output path"
    \\complete -c loupe -n "__fish_seen_subcommand_from faces" -l blur -d "Blur detected faces"
    \\complete -c loupe -n "__fish_seen_subcommand_from faces" -l redact -d "Redact detected faces"
    \\
    \\# segment options
    \\complete -c loupe -n "__fish_seen_subcommand_from segment" -s o -r -d "Save mask as PNG"
    \\
    \\# saliency options
    \\complete -c loupe -n "__fish_seen_subcommand_from saliency" -l objects -d "Use objectness-based saliency"
    \\
    \\# aruco options
    \\complete -c loupe -n "__fish_seen_subcommand_from aruco" -l dict -r -d "Restrict to one dictionary"
    \\
    \\# completions: shell name
    \\complete -c loupe -n "__fish_seen_subcommand_from completions" -a "fish bash zsh"
    \\
;

const bash_completions =
    \\# loupe completions for bash
    \\# Install: eval "$(loupe completions bash)"
    \\# Persist: loupe completions bash > /etc/bash_completion.d/loupe
    \\
    \\_loupe() {
    \\    local cur prev words cword
    \\    _init_completion || return
    \\
    \\    local commands="faces ocr barcode qr landmarks classify body hands animals rectangles horizon saliency score segment aruco completions help"
    \\
    \\    if [[ $cword -eq 1 ]]; then
    \\        COMPREPLY=($(compgen -W "$commands --json --help -h --version -V" -- "$cur"))
    \\        return
    \\    fi
    \\
    \\    local cmd="${words[1]}"
    \\
    \\    case "$cmd" in
    \\        faces)
    \\            COMPREPLY=($(compgen -W "-o --blur --redact --json" -- "$cur"))
    \\            ;;
    \\        segment)
    \\            COMPREPLY=($(compgen -W "-o --json" -- "$cur"))
    \\            ;;
    \\        saliency)
    \\            COMPREPLY=($(compgen -W "--objects --json" -- "$cur"))
    \\            ;;
    \\        aruco)
    \\            COMPREPLY=($(compgen -W "--dict --json" -- "$cur"))
    \\            ;;
    \\        ocr|barcode|qr|landmarks|classify|body|hands|animals|rectangles|horizon|score)
    \\            COMPREPLY=($(compgen -W "--json" -- "$cur"))
    \\            ;;
    \\        completions)
    \\            COMPREPLY=($(compgen -W "fish bash zsh" -- "$cur"))
    \\            ;;
    \\    esac
    \\}
    \\complete -F _loupe loupe
    \\
;

const zsh_completions =
    \\#compdef loupe
    \\# loupe completions for zsh
    \\# Install: loupe completions zsh | source /dev/stdin
    \\# Persist: loupe completions zsh > ~/.zfunc/_loupe && fpath+=(~/.zfunc)
    \\
    \\_loupe() {
    \\    local -a commands
    \\    commands=(
    \\        'faces:Detect faces in an image'
    \\        'ocr:Recognize text in an image'
    \\        'barcode:Scan barcodes in an image'
    \\        'qr:Scan QR codes in an image'
    \\        'landmarks:Detect facial landmarks'
    \\        'classify:Classify image content'
    \\        'body:Detect human body pose'
    \\        'hands:Detect hand pose'
    \\        'animals:Detect animals'
    \\        'rectangles:Detect rectangular shapes'
    \\        'horizon:Measure horizon tilt angle'
    \\        'saliency:Find visually salient regions'
    \\        'score:Rate image aesthetic quality'
    \\        'segment:Generate person segmentation mask'
    \\        'aruco:Detect ArUco markers'
    \\        'completions:Print shell completions'
    \\        'help:Show help'
    \\    )
    \\
    \\    _arguments -C \
    \\        '--json[Output as JSON]' \
    \\        '(--help -h)'{--help,-h}'[Show help]' \
    \\        '(--version -V)'{--version,-V}'[Show version]' \
    \\        '1:command:->cmd' \
    \\        '*::arg:->args'
    \\
    \\    case "$state" in
    \\        cmd)
    \\            _describe 'command' commands
    \\            ;;
    \\        args)
    \\            case "${words[1]}" in
    \\                faces)
    \\                    _arguments \
    \\                        '-o[Output path]:file:_files' \
    \\                        '--blur[Blur detected faces]' \
    \\                        '--redact[Redact detected faces]' \
    \\                        '--json[Output as JSON]' \
    \\                        '*:image:_files'
    \\                    ;;
    \\                segment)
    \\                    _arguments \
    \\                        '-o[Save mask as PNG]:file:_files' \
    \\                        '--json[Output as JSON]' \
    \\                        '*:image:_files'
    \\                    ;;
    \\                saliency)
    \\                    _arguments \
    \\                        '--objects[Use objectness-based saliency]' \
    \\                        '--json[Output as JSON]' \
    \\                        '*:image:_files'
    \\                    ;;
    \\                aruco)
    \\                    _arguments \
    \\                        '--dict[Restrict to one dictionary]:dictionary' \
    \\                        '--json[Output as JSON]' \
    \\                        '*:image:_files'
    \\                    ;;
    \\                ocr|barcode|qr|landmarks|classify|body|hands|animals|rectangles|horizon|score)
    \\                    _arguments \
    \\                        '--json[Output as JSON]' \
    \\                        '*:image:_files'
    \\                    ;;
    \\                completions)
    \\                    _values 'shell' fish bash zsh
    \\                    ;;
    \\            esac
    \\            ;;
    \\    esac
    \\}
    \\
    \\_loupe "$@"
    \\
;

fn saveMaskAsPng(seg: vision.SegmentResult, path: []const u8, source_image: vision.ImageHandle, stderr_writer: *std.Io.Writer) void {
    vision.saveMaskAsPng(seg, path, source_image) catch |err| {
        stderr_writer.print("Error: failed to save mask PNG: {s}\n", .{@errorName(err)}) catch {};
        stderr_writer.flush() catch {};
    };
}

// ---------------------------------------------------------------------------
// Print functions for new commands
// ---------------------------------------------------------------------------

fn printClassifyHuman(writer: *std.Io.Writer, results: []const vision.ClassifyResult) void {
    if (results.len == 0) {
        writer.print("No classifications.\n", .{}) catch {};
        return;
    }
    for (results) |r| {
        writer.print("{s}: {d:.2}\n", .{ r.label, r.confidence }) catch {};
    }
}

fn printClassifyJson(writer: *std.Io.Writer, results: []const vision.ClassifyResult) void {
    writer.print("{{\"labels\":[", .{}) catch {};
    for (results, 0..) |r, idx| {
        if (idx > 0) writer.print(",", .{}) catch {};
        writer.print("{{\"label\":\"", .{}) catch {};
        writeJsonString(writer, r.label);
        writer.print("\",\"confidence\":{d:.4}}}", .{r.confidence}) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

fn printLandmarksHuman(writer: *std.Io.Writer, results: []const vision.FaceLandmarksResult) void {
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

fn printLandmarksJson(writer: *std.Io.Writer, results: []const vision.FaceLandmarksResult) void {
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

fn printPointsJson(writer: *std.Io.Writer, name: []const u8, points: []const vision.LandmarkPoint) void {
    writer.print(",\"{s}\":[", .{name}) catch {};
    for (points, 0..) |p, j| {
        if (j > 0) writer.print(",", .{}) catch {};
        writer.print("[{d:.4},{d:.4}]", .{ p.x, p.y }) catch {};
    }
    writer.print("]", .{}) catch {};
}

fn printBodyHuman(writer: *std.Io.Writer, results: []const vision.BodyPoseResult) void {
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

fn printBodyJson(writer: *std.Io.Writer, results: []const vision.BodyPoseResult) void {
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

fn printHandsHuman(writer: *std.Io.Writer, results: []const vision.HandPoseResult) void {
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

fn printHandsJson(writer: *std.Io.Writer, results: []const vision.HandPoseResult) void {
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

fn printAnimalsHuman(writer: *std.Io.Writer, results: []const vision.AnimalResult) void {
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

fn printAnimalsJson(writer: *std.Io.Writer, results: []const vision.AnimalResult) void {
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

fn printRectanglesHuman(writer: *std.Io.Writer, results: []const vision.RectangleResult) void {
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

fn printRectanglesJson(writer: *std.Io.Writer, results: []const vision.RectangleResult) void {
    writer.print("{{\"rectangles\":[", .{}) catch {};
    for (results, 0..) |r, idx| {
        if (idx > 0) writer.print(",", .{}) catch {};
        writer.print("{{\"top_left\":[{d:.4},{d:.4}],\"top_right\":[{d:.4},{d:.4}],\"bottom_left\":[{d:.4},{d:.4}],\"bottom_right\":[{d:.4},{d:.4}]}}", .{
            r.top_left.x,     r.top_left.y,
            r.top_right.x,    r.top_right.y,
            r.bottom_left.x,  r.bottom_left.y,
            r.bottom_right.x, r.bottom_right.y,
        }) catch {};
    }
    writer.print("]}}\n", .{}) catch {};
}

fn printSaliencyHuman(writer: *std.Io.Writer, results: []const vision.SaliencyRect) void {
    if (results.len == 0) {
        writer.print("No salient regions detected.\n", .{}) catch {};
        return;
    }
    writer.print("Found {d} salient region{s}:\n", .{ results.len, if (results.len == 1) "" else "s" }) catch {};
    for (results, 0..) |r, idx| {
        writer.print("  Region {d}: ({d:.3}, {d:.3}) {d:.3}x{d:.3}\n", .{ idx + 1, r.box.x, r.box.y, r.box.width, r.box.height }) catch {};
    }
}

fn printSaliencyJson(writer: *std.Io.Writer, results: []const vision.SaliencyRect) void {
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
fn writeJsonString(writer: *std.Io.Writer, s: []const u8) void {
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
    stdout_writer: *std.Io.Writer,
    stderr_writer: *std.Io.Writer,
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
