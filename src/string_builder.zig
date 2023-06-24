const std = @import("std");

const Allocator = std.mem.Allocator;
pub const Pool = @import("pool.zig").Pool;

pub const StringBuilder = struct {
	// Two allocators! This is largely a feature meant to be used with the Pool.
	// Imagine you have a pool of 100 StringBuilders. Each one has a static buffer
	// of 2K, allocated with a general purpose allocator. We store that in _a.
	// Now you acquire an SB and start to write. You write more than 2K, so we
	// need to allocate `dynamic`. Yes, we could use our general purpose allocator
	// (aka _a), but what if the app would like to use a different allocator for
	// that, like an Arena?
	// Thus, `static` is always allocated with _a, and apps can opt to use a
	// different allocator, _da, to manage `dynamic`. `_da` is meant to be set
	// via pool.acquireWithAllocator since we expect _da to be transient.
	_a: Allocator,

	_da: ?Allocator,

	// where in buf we currently are
	pos: usize,

	// fixed size, created on startup
	static: []u8,

	// created when we try to write more than static.len
	dynamic: ?[]u8,

	// points to either static or dynamic,
	buf: []u8,

	pub fn init(allocator: Allocator, size: usize) !StringBuilder {
		const static = try allocator.alloc(u8, size);
		return .{
			._a = allocator,
			._da = null,
			.pos = 0,
			.dynamic = null,
			.buf = static,
			.static = static,
		};
	}

	pub fn deinit(self: StringBuilder) void {
		const allocator = self._a;
		allocator.free(self.static);
		if (self.dynamic) |dyn| {
			(self._da orelse allocator).free(dyn);
		}
	}

	pub fn reset(self: *StringBuilder) void {
		self.pos = 0;
		if (self.dynamic) |dyn| {
			(self._da orelse self._a).free(dyn);
			self.dynamic = null;
			self.buf = self.static;
		}
		self._da = null;
	}

	pub fn len(self: StringBuilder) usize {
		return self.pos;
	}

	pub fn string(self: StringBuilder) []const u8 {
		return self.buf[0..self.pos];
	}

	pub fn truncate(self: *StringBuilder, n: usize) void {
		const pos = self.pos;
		if (n >= pos) {
			self.pos = 0;
			return;
		}
		self.pos = pos - n;
	}

	pub fn writeByte(self: *StringBuilder, b: u8) !void {
		try self.ensureUnusedCapacity(1);
		self.writeByteAssumeCapacity(b);
	}

	pub fn writeByteAssumeCapacity(self: *StringBuilder, b: u8) void {
		const pos = self.pos;
		self.buf[pos] = b;
		self.pos = pos + 1;
	}

	pub fn writeByteNTimes(self: *StringBuilder, b: u8, n: usize) !void {
		try self.ensureUnusedCapacity(n);
		const pos = self.pos;
		const buf = self.buf;
		for (0..n) |offset| {
			buf[pos+offset] = b;
		}
		self.pos = pos + n;
	}

	pub fn write(self: *StringBuilder, data: []const u8) !void {
		try self.ensureUnusedCapacity(data.len);
		return self.writeAssumeCapacity(data);
	}

	pub fn writeAssumeCapacity(self: *StringBuilder, data: []const u8) void {
		const pos = self.pos;
		const end_pos = pos + data.len;
		std.mem.copyForwards(u8, self.buf[pos..end_pos], data);
		self.pos = end_pos;
	}

	pub fn ensureUnusedCapacity(self: *StringBuilder, n: usize) !void {
		return self.ensureTotalCapacity(self.pos + n);
	}

	pub fn ensureTotalCapacity(self: *StringBuilder, required_capacity: usize) !void {
		const buf = self.buf;
		if (required_capacity <= buf.len) {
			return;
		}

		// from std.ArrayList
		var new_capacity = self.buf.len;
		while (true) {
			new_capacity +|= new_capacity / 2 + 8;
			if (new_capacity >= required_capacity) break;
		}

		const allocator = self._da orelse self._a;
		if (buf.ptr == self.static.ptr or !allocator.resize(buf, new_capacity)) {
			const new_buffer = try allocator.alloc(u8, new_capacity);
			std.mem.copyForwards(u8, new_buffer[0..buf.len], buf);

			if (self.dynamic) |dyn| {
				allocator.free(dyn);
			}

			self.buf = new_buffer;
			self.dynamic = new_buffer;
		} else {
			const new_buffer = buf.ptr[0..new_capacity];
			self.buf = new_buffer;
			self.dynamic = new_buffer;
		}
	}

	pub fn writer(self: *StringBuilder) Writer.IOWriter {
			return .{.context = Writer.init(self)};
		}

	pub const Writer = struct {
		sb: *StringBuilder,

		pub const Error = Allocator.Error;
		pub const IOWriter = std.io.Writer(Writer, error{OutOfMemory}, Writer.write);

		fn init(sb: *StringBuilder) Writer {
			return .{.sb = sb};
		}

		pub fn write(self: Writer, data: []const u8) Allocator.Error!usize {
			try self.sb.write(data);
			return data.len;
		}
	};
};

const t = @import("t.zig");
test {
	std.testing.refAllDecls(@This());
}

test "growth" {
	var sb = try StringBuilder.init(t.allocator, 10);
	defer sb.deinit();

	// we reset at the end of the loop, and things should work the exact same
	// after a reset
	for (0..5) |_| {
		try t.expectEqual(0, sb.len());
		try sb.writeByte('o');
		try t.expectEqual(1, sb.len());
		try t.expectString("o", sb.string());
		try t.expectEqual(true, sb.dynamic == null);

		// stays in static
		try sb.write("ver 9000!");
		try t.expectEqual(10, sb.len());
		try t.expectString("over 9000!", sb.string());
		try t.expectEqual(true, sb.dynamic == null);

		// grows into dynamic
		try sb.write("!!!");
		try t.expectEqual(13, sb.len());
		try t.expectString("over 9000!!!!", sb.string());
		try t.expectEqual(false, sb.dynamic == null);


		try sb.write("If you were to run this code, you'd almost certainly see a segmentation fault (aka, segfault). We create a Response which involves creating an ArenaAllocator and from that, an Allocator. This allocator is then used to format our string. For the purpose of this example, we create a 2nd response and immediately free it. We need this for the same reason that warning1 in our first example printed an almost ok value: we want to re-initialize the memory in our init function stack.");
		try t.expectEqual(492, sb.len());
		try t.expectString("over 9000!!!!If you were to run this code, you'd almost certainly see a segmentation fault (aka, segfault). We create a Response which involves creating an ArenaAllocator and from that, an Allocator. This allocator is then used to format our string. For the purpose of this example, we create a 2nd response and immediately free it. We need this for the same reason that warning1 in our first example printed an almost ok value: we want to re-initialize the memory in our init function stack.", sb.string());

		sb.reset();
	}
}

test "truncate" {
	var sb = try StringBuilder.init(t.allocator, 10);
	defer sb.deinit();

	sb.truncate(100);
	try t.expectEqual(0, sb.len());

	try sb.write("hello world!1");

	sb.truncate(0);
	try t.expectEqual(13, sb.len());
	try t.expectString("hello world!1", sb.string());

	sb.truncate(1);
	try t.expectEqual(12, sb.len());
	try t.expectString("hello world!", sb.string());

	sb.truncate(5);
	try t.expectEqual(7, sb.len());
	try t.expectString("hello w", sb.string());
}

test "fuzz" {
	var control = std.ArrayList(u8).init(t.allocator);
	defer control.deinit();

	var r = t.getRandom();
	const random = r.random();

	var arena = std.heap.ArenaAllocator.init(t.allocator);
	defer arena.deinit();

	const aa = arena.allocator();

	for (1..100) |_| {
		var sb = try StringBuilder.init(t.allocator, random.uintAtMost(u16, 1000) + 1);
		defer sb.deinit();

		for (1..100) |_| {
			const input = testString(aa, random);
			try sb.write(input);
			try control.appendSlice(input);
			try t.expectString(control.items, sb.string());
		}
		sb.reset();
		control.clearRetainingCapacity();
		_ = arena.reset(.free_all);
	}
}

test "writer" {
	var sb = try StringBuilder.init(t.allocator, 10);
	defer sb.deinit();

	try std.json.stringify(.{.over = 9000, .spice = "must flow", .ok = true}, .{}, sb.writer());
	try t.expectString("{\"over\":9000,\"spice\":\"must flow\",\"ok\":true}", sb.string());
}

fn testString(allocator: Allocator, random: std.rand.Random) []const u8 {
	var s = allocator.alloc(u8, random.uintAtMost(u8, 100) + 1) catch unreachable;
	for (0..s.len) |i| {
		s[i] = random.uintAtMost(u8, 90) + 32;
	}
	return s;
}