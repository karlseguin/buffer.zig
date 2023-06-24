const std = @import("std");
const builtin = @import("builtin");

const StringBuilder = @import("string_builder.zig").StringBuilder;

const Mutex = std.Thread.Mutex;
const Allocator = std.mem.Allocator;

pub const Pool = struct {
	mutex: Mutex,
	available: usize,
	allocator: Allocator,
	builder_size: usize,
	builders: []*StringBuilder,

	pub fn init(allocator: Allocator, pool_size: u16, builder_size: usize) !Pool {
		const builders = try allocator.alloc(*StringBuilder, pool_size);

		for (0..pool_size) |i| {
			var sb = try allocator.create(StringBuilder);
			sb.* = try StringBuilder.init(allocator, builder_size);
			builders[i] = sb;
		}

		return Pool{
			.mutex = Mutex{},
			.builders = builders,
			.allocator = allocator,
			.available = pool_size,
			.builder_size = builder_size
		};
	}

	pub fn deinit(self: *Pool) void {
		const allocator = self.allocator;
		for (self.builders) |sb| {
			sb.deinit();
			allocator.destroy(sb);
		}
		allocator.free(self.builders);
	}

	pub fn acquire(self: *Pool) !*StringBuilder {
		return self.acquireWithAllocator(self.allocator);
	}

	pub fn acquireWithAllocator(self: *Pool, dyn_allocator: Allocator) !*StringBuilder {
		self.mutex.lock();

		const builders = self.builders;
		const available = self.available;
		if (available == 0) {
			// dont hold the lock over factory
			self.mutex.unlock();
			const allocator = self.allocator;

			const sb = try allocator.create(StringBuilder);
			sb.* = try StringBuilder.init(allocator, self.builder_size);
			if (comptime builtin.is_test) sb.buf[0] = 0;
			sb._da = dyn_allocator;
			return sb;
		}
		const index = available - 1;
		const sb = builders[index];
		self.available = index;
		self.mutex.unlock();
		sb._da = dyn_allocator;
		return sb;
	}

	pub fn release(self: *Pool, sb: *StringBuilder) void {
		sb.reset();
		self.mutex.lock();

		var builders = self.builders;
		const available = self.available;
		if (available == builders.len) {
			self.mutex.unlock();
			const allocator = self.allocator;
			sb.deinit();
			allocator.destroy(sb);
			return;
		}
		builders[available] = sb;
		self.available = available + 1;
		self.mutex.unlock();
	}
};

const t = @import("t.zig");
test "pool: acquire and release" {
	var p = try Pool.init(t.allocator, 2, 100);
	defer p.deinit();

	var sb1a = p.acquire() catch unreachable;
	var sb2a = p.acquire() catch unreachable;
	var sb3a = p.acquire() catch unreachable; // this should be dynamically generated

	try t.expectEqual(false, sb1a == sb2a);
	try t.expectEqual(false, sb2a == sb3a);

	p.release(sb1a);

	var sb1b = p.acquire() catch unreachable;
	try t.expectEqual(true, sb1a == sb1b);

	p.release(sb3a);
	p.release(sb2a);
	p.release(sb1b);
}

test "pool: dynamic allocator" {
	var p = try Pool.init(t.allocator, 2, 5);
	defer p.deinit();

	var arena = std.heap.ArenaAllocator.init(t.allocator);
	defer arena.deinit();

	var sb = p.acquireWithAllocator(arena.allocator()) catch unreachable;
	try sb.write("hello world how's it going?");
	try sb.write("he");
	try sb.write("hello world");
	try sb.write("are you doing well? I hope so, I don't love how this is being implemented, but I think the feature is worthwhile");
	p.release(sb);
}

test "pool: threadsafety" {
	var p = try Pool.init(t.allocator, 4, 20);
	defer p.deinit();

	// initialize this to 0 since we're asserting that it's 0
	for (p.builders) |sb| {
		sb.buf[0] = 0;
	}

	const t1 = try std.Thread.spawn(.{}, testPool, .{&p});
	const t2 = try std.Thread.spawn(.{}, testPool, .{&p});
	const t3 = try std.Thread.spawn(.{}, testPool, .{&p});
	const t4 = try std.Thread.spawn(.{}, testPool, .{&p});
	const t5 = try std.Thread.spawn(.{}, testPool, .{&p});

	t1.join(); t2.join(); t3.join(); t4.join(); t5.join();
}

fn testPool(p: *Pool) void {
	var r = t.getRandom();
	const random = r.random();

	for (0..5000) |_| {
		var sb = p.acquire() catch unreachable;
		// no other thread should have set this to 255
		std.debug.assert(sb.buf[0] == 0);

		sb.buf[0] = 255;
		std.time.sleep(random.uintAtMost(u32, 100000));
		sb.buf[0] = 0;
		p.release(sb);
	}
}