const std = @import("std");
pub const allocator = std.testing.allocator;
pub const io = std.testing.io;

// std.testing.expectEqual won't coerce expected to actual, which is a problem
// when expected is frequently a comptime.
// https://github.com/ziglang/zig/issues/4437
pub fn expectEqual(expected: anytype, actual: anytype) !void {
    try std.testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}
pub const expectString = std.testing.expectEqualStrings;
pub const expectSlice = std.testing.expectEqualSlices;

pub fn getRandom() std.Random.DefaultPrng {
    // This function is only used for test cases to gen random data,
    // so seeding it off now.Milliseconds since boot should be random enough ?
    // TODO - @karl review plz
    const seed: u64 = @intCast(std.Io.Clock.boot.now(std.testing.io).toMilliseconds());
    return std.Random.DefaultPrng.init(seed);
}
