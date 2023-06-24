const std = @import("std");
pub const allocator = std.testing.allocator;

// std.testing.expectEqual won't coerce expected to actual, which is a problem
// when expected is frequently a comptime.
// https://github.com/ziglang/zig/issues/4437
pub fn expectEqual(expected: anytype, actual: anytype) !void {
	try std.testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}
pub const expectString = std.testing.expectEqualStrings;

pub fn getRandom() std.rand.DefaultPrng {
	var seed: u64 = undefined;
	std.os.getrandom(std.mem.asBytes(&seed)) catch unreachable;
	return std.rand.DefaultPrng.init(seed);
}
