const std = @import("std");

const Allocator = std.mem.Allocator;
pub const Pool = @import("pool.zig").Pool;

pub const View = struct {
	// points to either static or dynamic,
	buf: []u8,

	// position in buf that we're at
	pos: usize,

	pub fn len(self: View) usize {
		return self.pos;
	}

	pub fn string(self: View) []u8 {
		return self.buf[0..self.pos];
	}

	pub fn truncate(self: *View, n: usize) void {
		const pos = self.pos;
		if (n >= pos) {
			self.pos = 0;
			return;
		}
		self.pos = pos - n;
	}

	pub fn skip(self: *View, n: usize) usize {
		const pos = self.pos;
		const end_pos = pos + n;
		self.pos = end_pos;
		return pos;
	}

	pub fn copy(self: View, allocator: Allocator) ![]u8 {
		const pos = self.pos;
		const c = try allocator.alloc(u8, pos);
		@memcpy(c, self.buf[0..pos]);
		return c;
	}

	pub fn writeByte(self: *View, b: u8) void {
		const pos = self.pos;
		self.buf[pos] = b;
		self.pos = pos + 1;
	}

	pub fn writeByteNTimes(self: *View, b: u8, n: usize) void {
		const pos = self.pos;
		const buf = self.buf;
		for (0..n) |offset| {
			buf[pos+offset] = b;
		}
		self.pos = pos + n;
	}

	pub fn write(self: *View, data: []const u8) void {
		const pos = self.pos;
		const end_pos = pos + data.len;
		@memcpy(self.buf[pos..end_pos], data);
		self.pos = end_pos;
	}

	pub fn writeU16Little(self: *View, value: u16) void {
		self.writeIntLittle(u16, value);
	}

	pub fn writeU32Little(self: *View, value: u32) void {
		self.writeIntLittle(u32, value);
	}

	pub fn writeU64Little(self: *View, value: u64) void {
		self.writeIntLittle(u64, value);
	}

	pub fn writeIntLittle(self: *View, comptime T: type, value: T) void {
		const l = @divExact(@typeInfo(T).Int.bits, 8);
		const pos = self.pos;
		const end_pos = pos + l;
		std.mem.writeInt(T, self.buf[pos..end_pos][0..l], value, .little);
		self.pos = end_pos;
	}

	pub fn writeU16Big(self: *View, value: u16) void {
		self.writeIntBig(u16, value);
	}

	pub fn writeU32Big(self: *View, value: u32) void {
		self.writeIntBig(u32, value);
	}

	pub fn writeU64Big(self: *View, value: u64) void {
		self.writeIntBig(u64, value);
	}

pub fn writeIntBig(self: *View, comptime T: type, value: T) void {
		const l = @divExact(@typeInfo(T).Int.bits, 8);
		const pos = self.pos;
		const end_pos = pos + l;
		std.mem.writeInt(T, self.buf[pos..end_pos][0..l], value, .big);
		self.pos = end_pos;
	}
};

pub const Buffer = struct {
	// Two allocators! This is largely a feature meant to be used with the Pool.
	// Imagine you have a pool of 100 StringBuilders. Each one has a static buffer
	// of 2K, allocated with a general purpose allocator. We store that in _a.
	// Now you acquire an w and start to write. You write more than 2K, so we
	// need to allocate `dynamic`. Yes, we could use our general purpose allocator
	// (aka _a), but what if the app would like to use a different allocator for
	// that, like an Arena?
	// Thus, `static` is always allocated with _a, and apps can opt to use a
	// different allocator, _da, to manage `dynamic`. `_da` is meant to be set
	// via pool.acquireWithAllocator since we expect _da to be transient.
	_a: Allocator,

	_da: ?Allocator,

	_view: View,

	// fixed size, created on startup
	static: []u8,

	// created when we try to write more than static.len
	dynamic: ?[]u8,

	pub fn init(allocator: Allocator, size: usize) !Buffer {
		const static = try allocator.alloc(u8, size);
		return .{
			._a = allocator,
			._da = null,
			.dynamic = null,
			.static = static,
			._view = .{
				.pos = 0,
				.buf = static,
			},
		};
	}

	pub fn deinit(self: Buffer) void {
		const allocator = self._a;
		allocator.free(self.static);
		if (self.dynamic) |dyn| {
			(self._da orelse allocator).free(dyn);
		}
	}

	pub fn reset(self: *Buffer) void {
		self._view.pos = 0;
		if (self.dynamic) |dyn| {
			(self._da orelse self._a).free(dyn);
			self.dynamic = null;
			self._view.buf = self.static;
		}
		self._da = null;
	}

	pub fn resetRetainingCapacity(self: *Buffer) void {
		self._view.pos = 0;
	}

	pub fn len(self: Buffer) usize {
		return self._view.pos;
	}

	pub fn string(self: Buffer) []const u8 {
		return self._view.string();
	}

	pub fn truncate(self: *Buffer, n: usize) void {
		self._view.truncate(n);
	}

	pub fn writeByte(self: *Buffer, b: u8) !void {
		try self.ensureUnusedCapacity(1);
		self._view.writeByte(b);
	}

	pub fn writeByteAssumeCapacity(self: *Buffer, b: u8) void {
		self._view.writeByte(b);
	}


	pub fn writeByteNTimes(self: *Buffer, b: u8, n: usize) !void {
		try self.ensureUnusedCapacity(n);
		self._view.writeByteNTimes(b, n);
	}

	pub fn write(self: *Buffer, data: []const u8) !void {
		try self.ensureUnusedCapacity(data.len);
		self._view.write(data);
	}

	// unsafe
	pub fn writeAt(self: *Buffer, data: []const u8, pos: usize) void {
		@memcpy(self._view.buf[pos..pos+data.len], data);
	}

	pub fn writeAssumeCapacity(self: *Buffer, data: []const u8) void {
		self._view.write(data);
	}

	pub fn writeU16Little(self: *Buffer, value: u16) !void {
		return self.writeIntLittle(u16, value);
	}

	pub fn writeU32Little(self: *Buffer, value: u32) !void {
		return self.writeIntLittle(u32, value);
	}

	pub fn writeU64Little(self: *Buffer, value: u64) !void {
		return self.writeIntLittle(u64, value);
	}

	pub fn writeIntLittle(self: *Buffer, comptime T: type, value: T) !void {
		const l = @divExact(@typeInfo(T).Int.bits, 8);
		try self.ensureUnusedCapacity(l);
		self._view.writeIntLittle(T, value);
	}

	pub fn writeU16Big(self: *Buffer, value: u16) !void {
		return self.writeIntBig(u16, value);
	}

	pub fn writeU32Big(self: *Buffer, value: u32) !void {
		return self.writeIntBig(u32, value);
	}

	pub fn writeU64Big(self: *Buffer, value: u64) !void {
		return self.writeIntBig(u64, value);
	}

	pub fn writeIntBig(self: *Buffer, comptime T: type, value: T) !void {
		const l = @divExact(@typeInfo(T).Int.bits, 8);
		try self.ensureUnusedCapacity(l);
		self._view.writeIntBig(T, value);
	}

	pub fn skip(self: *Buffer, n: usize) !usize {
		try self.ensureUnusedCapacity(n);
		return self._view.skip(n);
	}

	pub fn view(self: *Buffer, pos: usize) View {
		return .{
			.pos = 0,
			.buf = self._view.buf[pos..],
		};
	}

	pub fn ensureUnusedCapacity(self: *Buffer, n: usize) !void {
		return self.ensureTotalCapacity(self._view.pos + n);
	}

	pub fn ensureTotalCapacity(self: *Buffer, required_capacity: usize) !void {
		const buf = self._view.buf;
		if (required_capacity <= buf.len) {
			return;
		}

		// from std.ArrayList
		var new_capacity = buf.len;
		while (true) {
			new_capacity +|= new_capacity / 2 + 8;
			if (new_capacity >= required_capacity) break;
		}

		const allocator = self._da orelse self._a;
		if (buf.ptr == self.static.ptr or !allocator.resize(buf, new_capacity)) {
			const new_buffer = try allocator.alloc(u8, new_capacity);
			@memcpy(new_buffer[0..buf.len], buf);

			if (self.dynamic) |dyn| {
				allocator.free(dyn);
			}

			self._view.buf = new_buffer;
			self.dynamic = new_buffer;
		} else {
			const new_buffer = buf.ptr[0..new_capacity];
			self._view.buf = new_buffer;
			self.dynamic = new_buffer;
		}
	}

	pub fn copy(self: Buffer, allocator: Allocator) ![]const u8 {
		return self._view.copy(allocator);
	}

	pub fn writer(self: *Buffer) Writer.IOWriter {
			return .{.context = Writer.init(self)};
		}

	pub const Writer = struct {
		w: *Buffer,

		pub const Error = Allocator.Error;
		pub const IOWriter = std.io.Writer(Writer, error{OutOfMemory}, Writer.write);

		fn init(w: *Buffer) Writer {
			return .{.w = w};
		}

		pub fn write(self: Writer, data: []const u8) Allocator.Error!usize {
			try self.w.write(data);
			return data.len;
		}
	};
};

const t = @import("t.zig");
test {
	std.testing.refAllDecls(@This());
}

test "growth" {
	var w = try Buffer.init(t.allocator, 10);
	defer w.deinit();

	// we reset at the end of the loop, and things should work the exact same
	// after a reset
	for (0..5) |_| {
		try t.expectEqual(0, w.len());
		try w.writeByte('o');
		try t.expectEqual(1, w.len());
		try t.expectString("o", w.string());
		try t.expectEqual(true, w.dynamic == null);

		// stays in static
		try w.write("ver 9000!");
		try t.expectEqual(10, w.len());
		try t.expectString("over 9000!", w.string());
		try t.expectEqual(true, w.dynamic == null);

		// grows into dynamic
		try w.write("!!!");
		try t.expectEqual(13, w.len());
		try t.expectString("over 9000!!!!", w.string());
		try t.expectEqual(false, w.dynamic == null);


		try w.write("If you were to run this code, you'd almost certainly see a segmentation fault (aka, segfault). We create a Response which involves creating an ArenaAllocator and from that, an Allocator. This allocator is then used to format our string. For the purpose of this example, we create a 2nd response and immediately free it. We need this for the same reason that warning1 in our first example printed an almost ok value: we want to re-initialize the memory in our init function stack.");
		try t.expectEqual(492, w.len());
		try t.expectString("over 9000!!!!If you were to run this code, you'd almost certainly see a segmentation fault (aka, segfault). We create a Response which involves creating an ArenaAllocator and from that, an Allocator. This allocator is then used to format our string. For the purpose of this example, we create a 2nd response and immediately free it. We need this for the same reason that warning1 in our first example printed an almost ok value: we want to re-initialize the memory in our init function stack.", w.string());

		w.reset();
	}
}

test "truncate" {
	var w = try Buffer.init(t.allocator, 10);
	defer w.deinit();

	w.truncate(100);
	try t.expectEqual(0, w.len());

	try w.write("hello world!1");

	w.truncate(0);
	try t.expectEqual(13, w.len());
	try t.expectString("hello world!1", w.string());

	w.truncate(1);
	try t.expectEqual(12, w.len());
	try t.expectString("hello world!", w.string());

	w.truncate(5);
	try t.expectEqual(7, w.len());
	try t.expectString("hello w", w.string());
}

test "reset without clear" {
	var w = try Buffer.init(t.allocator, 5);
	defer w.deinit();

	try w.write("hello world!1");
	try t.expectString("hello world!1", w.string());

	w.resetRetainingCapacity();
	try t.expectEqual(0, w.len());
	try t.expectEqual(false, w.dynamic == null);
	try w.write("over 9000");
	try w.write("over 9000");
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
		var w = try Buffer.init(t.allocator, random.uintAtMost(u16, 1000) + 1);
		defer w.deinit();

		for (1..100) |_| {
			const input = testString(aa, random);
			try w.write(input);
			try control.appendSlice(input);
			try t.expectString(control.items, w.string());
		}
		w.reset();
		control.clearRetainingCapacity();
		_ = arena.reset(.free_all);
	}
}

test "writer" {
	var w = try Buffer.init(t.allocator, 10);
	defer w.deinit();

	try std.json.stringify(.{.over = 9000, .spice = "must flow", .ok = true}, .{}, w.writer());
	try t.expectString("{\"over\":9000,\"spice\":\"must flow\",\"ok\":true}", w.string());
}

test "copy" {
	var w = try Buffer.init(t.allocator, 10);
	defer w.deinit();

	try w.write("hello!!");
	const c = try w.copy(t.allocator);
	defer t.allocator.free(c);
	try t.expectString("hello!!", c);
}

test "write little" {
	var w = try Buffer.init(t.allocator, 20);
	defer w.deinit();
	try w.writeU64Little(11234567890123456789);
	try t.exectSlice(u8, &[_]u8{21, 129, 209, 7, 249, 51, 233, 155}, w.string());

	try w.writeU32Little(3283856184);
	try t.exectSlice(u8, &[_]u8{21, 129, 209, 7, 249, 51, 233, 155, 56, 171, 187, 195}, w.string());

	try w.writeU16Little(15000);
	try t.exectSlice(u8, &[_]u8{21, 129, 209, 7, 249, 51, 233, 155, 56, 171, 187, 195, 152, 58}, w.string());
}

test "write big" {
	var w = try Buffer.init(t.allocator, 20);
	defer w.deinit();
	try w.writeU64Big(11234567890123456789);
	try t.exectSlice(u8, &[_]u8{155, 233, 51, 249, 7, 209, 129, 21}, w.string());

	try w.writeU32Big(3283856184);
	try t.exectSlice(u8, &[_]u8{155, 233, 51, 249, 7, 209, 129, 21, 195, 187, 171, 56}, w.string());

	try w.writeU16Big(15000);
	try t.exectSlice(u8, &[_]u8{155, 233, 51, 249, 7, 209, 129, 21, 195, 187, 171, 56, 58, 152}, w.string());
}

test "skip & view" {
	var w = try Buffer.init(t.allocator, 10);
	defer w.deinit();

	const start = try w.skip(4);
	try w.write("hello world!!");

	var v = w.view(start);
	v.writeU32Big(@intCast(w.len() - 4));

	try w.writeByte('\n');
	try t.exectSlice(u8, &[_]u8{0, 0, 0, 13, 'h', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd', '!', '!', '\n'}, w.string());
}

test "writeAt" {
	var w = try Buffer.init(t.allocator, 200);
	defer w.deinit();

	try w.write("hello");
	try w.write(&.{0, 0, 0, 0, 0});
	try w.write("world");

	w.writeAt(" ", 5);
	w.writeAt("123 ", 6);
	try t.expectString("hello 123 world", w.string());
}

fn testString(allocator: Allocator, random: std.rand.Random) []const u8 {
	var s = allocator.alloc(u8, random.uintAtMost(u8, 100) + 1) catch unreachable;
	for (0..s.len) |i| {
		s[i] = random.uintAtMost(u8, 90) + 32;
	}
	return s;
}
