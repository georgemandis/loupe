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
        try stderr.interface.print("Error: 'faces' subcommand is not yet implemented.\n", .{});
        try stderr.interface.flush();
        std.process.exit(1);
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
