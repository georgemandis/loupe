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
