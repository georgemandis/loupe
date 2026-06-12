//! ArUco marker decoding — platform-independent.
//! Candidate quads come from the platform layer (Vision rectangle detection
//! on macOS); this module unwarps each quad, samples the bit grid, and
//! matches against the standard OpenCV dictionaries in aruco_dicts.zig.
//! Bit convention: row-major, MSB first, bit 1 = white cell.

const std = @import("std");
const dicts = @import("aruco_dicts.zig");

pub const Family = struct {
    n: u8,
    codes: []const u64,
    max_correction: u8,
};

pub const families = [_]Family{
    .{ .n = 4, .codes = &dicts.dict_4x4, .max_correction = dicts.dict_4x4_maxcorr },
    .{ .n = 5, .codes = &dicts.dict_5x5, .max_correction = dicts.dict_5x5_maxcorr },
    .{ .n = 6, .codes = &dicts.dict_6x6, .max_correction = dicts.dict_6x6_maxcorr },
    .{ .n = 7, .codes = &dicts.dict_7x7, .max_correction = dicts.dict_7x7_maxcorr },
};

pub const Point = struct { x: f64, y: f64 };

/// Quad corners in pixel coordinates, top-left origin, clockwise.
pub const Quad = struct {
    top_left: Point,
    top_right: Point,
    bottom_right: Point,
    bottom_left: Point,
};

/// Grayscale pixels, row-major, one byte per pixel, row 0 = top of image.
pub const GrayImage = struct {
    width: usize,
    height: usize,
    pixels: []const u8,
};

/// Bit at (row, col) of an n×n code packed row-major, MSB first.
pub fn bitAt(code: u64, n: u8, row: usize, col: usize) u1 {
    std.debug.assert(n >= 1 and @as(usize, n) * n <= 64);
    const nn = @as(usize, n) * n;
    const shift: u6 = @intCast(nn - 1 - (row * n + col));
    return @intCast((code >> shift) & 1);
}

/// Rotate an n×n code 90° clockwise.
pub fn rotate90(code: u64, n: u8) u64 {
    var out: u64 = 0;
    for (0..n) |r| {
        for (0..n) |c| {
            // cell (r, c) of the rotated grid came from (n-1-c, r)
            out = (out << 1) | @as(u64, bitAt(code, n, n - 1 - c, r));
        }
    }
    return out;
}

const Perspective = struct {
    a: f64,
    b: f64,
    c: f64,
    d: f64,
    e: f64,
    f: f64,
    g: f64,
    h: f64,

    fn map(self: Perspective, u: f64, v: f64) Point {
        const w = self.g * u + self.h * v + 1.0;
        return .{
            .x = (self.a * u + self.b * v + self.c) / w,
            .y = (self.d * u + self.e * v + self.f) / w,
        };
    }
};

/// Projective map from the unit square to the quad:
/// (0,0)→top_left, (1,0)→top_right, (1,1)→bottom_right, (0,1)→bottom_left.
/// Closed form from Heckbert, "Fundamentals of Texture Mapping and Image
/// Warping", §2.2.
fn perspectiveFromQuad(q: Quad) ?Perspective {
    const x0 = q.top_left.x;
    const y0 = q.top_left.y;
    const x1 = q.top_right.x;
    const y1 = q.top_right.y;
    const x2 = q.bottom_right.x;
    const y2 = q.bottom_right.y;
    const x3 = q.bottom_left.x;
    const y3 = q.bottom_left.y;

    const dx1 = x1 - x2;
    const dy1 = y1 - y2;
    const dx2 = x3 - x2;
    const dy2 = y3 - y2;
    const sx = x0 - x1 + x2 - x3;
    const sy = y0 - y1 + y2 - y3;

    const den = dx1 * dy2 - dx2 * dy1;
    if (@abs(den) < 1e-12) return null;

    const g = (sx * dy2 - sy * dx2) / den;
    const h = (dx1 * sy - dy1 * sx) / den;

    return .{
        .a = x1 - x0 + g * x1,
        .b = x3 - x0 + h * x3,
        .c = x0,
        .d = y1 - y0 + g * y1,
        .e = y3 - y0 + h * y3,
        .f = y0,
        .g = g,
        .h = h,
    };
}

fn sampleBilinear(img: GrayImage, x: f64, y: f64) f64 {
    std.debug.assert(img.width >= 1 and img.height >= 1);
    std.debug.assert(img.pixels.len == img.width * img.height);
    const max_x: f64 = @floatFromInt(img.width - 1);
    const max_y: f64 = @floatFromInt(img.height - 1);
    const cx = std.math.clamp(x, 0, max_x);
    const cy = std.math.clamp(y, 0, max_y);
    const x0: usize = @intFromFloat(@floor(cx));
    const y0: usize = @intFromFloat(@floor(cy));
    const x1 = @min(x0 + 1, img.width - 1);
    const y1 = @min(y0 + 1, img.height - 1);
    const fx = cx - @floor(cx);
    const fy = cy - @floor(cy);
    const p00: f64 = @floatFromInt(img.pixels[y0 * img.width + x0]);
    const p10: f64 = @floatFromInt(img.pixels[y0 * img.width + x1]);
    const p01: f64 = @floatFromInt(img.pixels[y1 * img.width + x0]);
    const p11: f64 = @floatFromInt(img.pixels[y1 * img.width + x1]);
    return p00 * (1 - fx) * (1 - fy) + p10 * fx * (1 - fy) +
        p01 * (1 - fx) * fy + p11 * fx * fy;
}

test "dictionary tables have 1000 entries that fit their grid" {
    inline for (families) |family| {
        try std.testing.expectEqual(@as(usize, 1000), family.codes.len);
        const nn: u6 = @intCast(@as(usize, family.n) * family.n);
        for (family.codes) |code| {
            if (nn < 64) {
                try std.testing.expect(code < (@as(u64, 1) << nn));
            }
        }
    }
}

test "max_correction values match generated dictionary constants" {
    try std.testing.expectEqual(@as(u8, 0), families[0].max_correction); // 4x4
    try std.testing.expectEqual(@as(u8, 2), families[1].max_correction); // 5x5
    try std.testing.expectEqual(@as(u8, 4), families[2].max_correction); // 6x6
    try std.testing.expectEqual(@as(u8, 6), families[3].max_correction); // 7x7
}

test "bitAt reads row-major MSB-first" {
    // 2x2 grid, code 0b1000: only (0,0) is set
    try std.testing.expectEqual(@as(u1, 1), bitAt(0b1000, 2, 0, 0));
    try std.testing.expectEqual(@as(u1, 0), bitAt(0b1000, 2, 0, 1));
    try std.testing.expectEqual(@as(u1, 0), bitAt(0b1000, 2, 1, 0));
    try std.testing.expectEqual(@as(u1, 0), bitAt(0b1000, 2, 1, 1));
}

test "rotate90 rotates clockwise" {
    // (0,0) set → after CW rotation, (0,1) set
    try std.testing.expectEqual(@as(u64, 0b0100), rotate90(0b1000, 2));
    // four rotations restore a real dictionary entry
    var code = dicts.dict_5x5[123];
    for (0..4) |_| code = rotate90(code, 5);
    try std.testing.expectEqual(dicts.dict_5x5[123], code);
}

test "perspectiveFromQuad maps unit square corners to quad corners" {
    const q = Quad{
        .top_left = .{ .x = 10, .y = 20 },
        .top_right = .{ .x = 110, .y = 25 },
        .bottom_right = .{ .x = 105, .y = 130 },
        .bottom_left = .{ .x = 8, .y = 120 },
    };
    const p = perspectiveFromQuad(q).?;
    const eps = 1e-9;
    const tl = p.map(0, 0);
    try std.testing.expectApproxEqAbs(@as(f64, 10), tl.x, eps);
    try std.testing.expectApproxEqAbs(@as(f64, 20), tl.y, eps);
    const tr = p.map(1, 0);
    try std.testing.expectApproxEqAbs(@as(f64, 110), tr.x, eps);
    try std.testing.expectApproxEqAbs(@as(f64, 25), tr.y, eps);
    const br = p.map(1, 1);
    try std.testing.expectApproxEqAbs(@as(f64, 105), br.x, eps);
    try std.testing.expectApproxEqAbs(@as(f64, 130), br.y, eps);
    const bl = p.map(0, 1);
    try std.testing.expectApproxEqAbs(@as(f64, 8), bl.x, eps);
    try std.testing.expectApproxEqAbs(@as(f64, 120), bl.y, eps);
}

test "perspectiveFromQuad is genuinely projective in the interior" {
    // Keystone trapezoid: an affine map (g = h = 0) would put the center at
    // (50, 30); the projective map must put it at (50, 300/7).
    const q = Quad{
        .top_left = .{ .x = 0, .y = 0 },
        .top_right = .{ .x = 100, .y = 0 },
        .bottom_right = .{ .x = 70, .y = 60 },
        .bottom_left = .{ .x = 30, .y = 60 },
    };
    const p = perspectiveFromQuad(q).?;
    const center = p.map(0.5, 0.5);
    try std.testing.expectApproxEqAbs(@as(f64, 50), center.x, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 300.0 / 7.0), center.y, 1e-9);
}

test "perspectiveFromQuad rejects degenerate quads" {
    const q = Quad{
        .top_left = .{ .x = 0, .y = 0 },
        .top_right = .{ .x = 0, .y = 0 },
        .bottom_right = .{ .x = 0, .y = 0 },
        .bottom_left = .{ .x = 0, .y = 0 },
    };
    try std.testing.expectEqual(@as(?Perspective, null), perspectiveFromQuad(q));
}

test "sampleBilinear interpolates and clamps" {
    // 2x2 image: 0 100 / 200 255, row 0 = top
    const px = [_]u8{ 0, 100, 200, 255 };
    const img = GrayImage{ .width = 2, .height = 2, .pixels = &px };
    try std.testing.expectApproxEqAbs(@as(f64, 0), sampleBilinear(img, 0, 0), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 50), sampleBilinear(img, 0.5, 0), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 138.75), sampleBilinear(img, 0.5, 0.5), 1e-9);
    // out-of-bounds clamps to the nearest edge pixel
    try std.testing.expectApproxEqAbs(@as(f64, 255), sampleBilinear(img, 99, 99), 1e-9);
}

pub const DictSpec = struct { n: u8, size: u32 };

pub const Options = struct {
    /// null = auto-detect across all four families with strict (≤1 bit)
    /// matching. Set = search one dictionary with its full error-correction
    /// budget.
    spec: ?DictSpec = null,
};

pub const Decoded = struct {
    id: u32,
    n: u8,
    /// Quad corners reordered so corner 0 is the marker's canonical top-left,
    /// clockwise, pixel coordinates.
    corners: [4]Point,
};

/// Reject candidates whose brightest and darkest cells differ by less than
/// this — there is no marker there, just a flat region.
const min_contrast = 30.0;

fn sampleCells(img: GrayImage, persp: Perspective, total: usize, cells: []f64) void {
    // Average 5 sub-samples per cell to tolerate slightly loose quads.
    const offsets = [_][2]f64{ .{ 0, 0 }, .{ -0.2, -0.2 }, .{ 0.2, -0.2 }, .{ -0.2, 0.2 }, .{ 0.2, 0.2 } };
    const ftotal: f64 = @floatFromInt(total);
    for (0..total) |r| {
        for (0..total) |c| {
            var sum: f64 = 0;
            for (offsets) |off| {
                const u = (@as(f64, @floatFromInt(c)) + 0.5 + off[0]) / ftotal;
                const v = (@as(f64, @floatFromInt(r)) + 0.5 + off[1]) / ftotal;
                const p = persp.map(u, v);
                sum += sampleBilinear(img, p.x, p.y);
            }
            cells[r * total + c] = sum / offsets.len;
        }
    }
}

/// A match at rotation k means the sampled grid rotated 90°·k clockwise
/// equals the canonical marker, so the canonical top-left corner is k steps
/// earlier in the clockwise corner list.
fn canonicalCorners(quad: Quad, k: usize) [4]Point {
    const in = [4]Point{ quad.top_left, quad.top_right, quad.bottom_right, quad.bottom_left };
    var out: [4]Point = undefined;
    for (0..4) |i| {
        out[i] = in[(i + 4 - k) % 4];
    }
    return out;
}

pub fn decodeQuad(img: GrayImage, quad: Quad, opts: Options) ?Decoded {
    if (img.width < 2 or img.height < 2) return null;
    const persp = perspectiveFromQuad(quad) orelse return null;

    var best: ?Decoded = null;
    var best_dist: u32 = std.math.maxInt(u32);

    for (families) |family| {
        const size: u32 = if (opts.spec) |s| blk: {
            if (s.n != family.n) continue;
            break :blk s.size;
        } else 1000;
        const max_dist: u32 = if (opts.spec != null) family.max_correction else 1;

        const total = @as(usize, family.n) + 2;
        var cells_buf: [81]f64 = undefined; // (7+2)² max
        const cells = cells_buf[0 .. total * total];
        sampleCells(img, persp, total, cells);

        // Threshold halfway between the darkest and brightest cell.
        var lo: f64 = 255.0;
        var hi: f64 = 0.0;
        for (cells) |v| {
            lo = @min(lo, v);
            hi = @max(hi, v);
        }
        if (hi - lo < min_contrast) continue;
        const threshold = (lo + hi) / 2.0;

        // The border ring must be black; tolerate up to 20% bad cells.
        const border_count = 4 * total - 4;
        var border_errors: usize = 0;
        for (0..total) |r| {
            for (0..total) |c| {
                const is_border = r == 0 or c == 0 or r == total - 1 or c == total - 1;
                if (is_border and cells[r * total + c] >= threshold) border_errors += 1;
            }
        }
        if (border_errors > border_count / 5) continue;

        // Pack inner bits (1 = white), row-major, MSB first.
        var code: u64 = 0;
        for (1..total - 1) |r| {
            for (1..total - 1) |c| {
                const bit: u64 = if (cells[r * total + c] >= threshold) 1 else 0;
                code = (code << 1) | bit;
            }
        }

        // Try the 4 rotations against the dictionary, keep the best match.
        var rotated = code;
        for (0..4) |rot| {
            for (family.codes[0..size], 0..) |entry, id| {
                const dist: u32 = @popCount(entry ^ rotated);
                if (dist <= max_dist and dist < best_dist) {
                    best_dist = dist;
                    best = .{
                        .id = @intCast(id),
                        .n = family.n,
                        .corners = canonicalCorners(quad, rot),
                    };
                }
            }
            rotated = rotate90(rotated, family.n);
        }
    }

    return best;
}

/// Test helper: render an axis-aligned marker (with its 1-cell black border)
/// onto a white canvas. `cell` is the side of one cell in pixels; the marker
/// occupies (n+2)*cell pixels starting at (x0, y0).
fn renderMarker(pixels: []u8, img_w: usize, n: u8, code: u64, x0: usize, y0: usize, cell: usize) void {
    @memset(pixels, 255);
    const total = @as(usize, n) + 2;
    for (0..total) |r| {
        for (0..total) |c| {
            const is_border = r == 0 or c == 0 or r == total - 1 or c == total - 1;
            const white = !is_border and bitAt(code, n, r - 1, c - 1) == 1;
            const value: u8 = if (white) 255 else 0;
            for (0..cell) |dy| {
                const row_start = (y0 + r * cell + dy) * img_w + x0 + c * cell;
                @memset(pixels[row_start .. row_start + cell], value);
            }
        }
    }
}

/// Test helper: the exact outer quad of a marker rendered by renderMarker.
fn markerQuad(n: u8, x0: usize, y0: usize, cell: usize) Quad {
    const side: f64 = @floatFromInt((@as(usize, n) + 2) * cell);
    const fx: f64 = @floatFromInt(x0);
    const fy: f64 = @floatFromInt(y0);
    return .{
        .top_left = .{ .x = fx, .y = fy },
        .top_right = .{ .x = fx + side, .y = fy },
        .bottom_right = .{ .x = fx + side, .y = fy + side },
        .bottom_left = .{ .x = fx, .y = fy + side },
    };
}

test "decodeQuad decodes a rendered 4x4 marker" {
    var pixels: [200 * 200]u8 = undefined;
    renderMarker(&pixels, 200, 4, dicts.dict_4x4[23], 40, 40, 20);
    const img = GrayImage{ .width = 200, .height = 200, .pixels = &pixels };
    const result = decodeQuad(img, markerQuad(4, 40, 40, 20), .{}).?;
    try std.testing.expectEqual(@as(u32, 23), result.id);
    try std.testing.expectEqual(@as(u8, 4), result.n);
}

test "decodeQuad returns null on a blank image" {
    var pixels: [100 * 100]u8 = undefined;
    @memset(&pixels, 255);
    const img = GrayImage{ .width = 100, .height = 100, .pixels = &pixels };
    try std.testing.expectEqual(@as(?Decoded, null), decodeQuad(img, markerQuad(4, 10, 10, 10), .{}));
}
