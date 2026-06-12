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

/// Bit at (row, col) of an n×n code packed row-major, MSB first.
pub fn bitAt(code: u64, n: u8, row: usize, col: usize) u1 {
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
