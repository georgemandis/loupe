const std = @import("std");
const vision = @import("vision");

fn printUsage(writer: *std.io.Writer) !void {
    try writer.print(
        \\Usage: loupe <command> [options] <image>
        \\
        \\Computer vision CLI — detect faces, read text, and scan barcodes.
        \\
        \\Commands:
        \\  faces    Detect faces in an image
        \\  ocr      Recognize text in an image
        \\  barcode  Scan barcodes in an image
        \\  qr       Scan QR codes in an image
        \\  help     Show this help message
        \\
        \\Global options:
        \\  --json               Output results as JSON
        \\  --help, -h           Show this help message
        \\
        \\Options for 'faces':
        \\  -o <output>          Write output image to this path
        \\  --blur               Blur detected faces in output image
        \\  --redact             Redact (black box) detected faces in output image
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
        try stderr.interface.print("Error: 'ocr' subcommand is not yet implemented.\n", .{});
        try stderr.interface.flush();
        std.process.exit(1);
    }

    if (std.mem.eql(u8, subcommand, "barcode")) {
        try stderr.interface.print("Error: 'barcode' subcommand is not yet implemented.\n", .{});
        try stderr.interface.flush();
        std.process.exit(1);
    }

    if (std.mem.eql(u8, subcommand, "qr")) {
        try stderr.interface.print("Error: 'qr' subcommand is not yet implemented.\n", .{});
        try stderr.interface.flush();
        std.process.exit(1);
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

    // If blur/redact requested, apply it
    if (blur_mode) |mode| {
        const blurred = vision.blurFaces(allocator, handle, faces, mode) catch |err| {
            handleError(err, json_mode, stdout_writer, stderr_writer);
            return;
        };
        defer vision.freeImage(blurred);

        vision.saveImage(blurred, output_path.?) catch |err| {
            handleError(err, json_mode, stdout_writer, stderr_writer);
            return;
        };
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
