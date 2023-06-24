# StringBuilder For Zig

Behaves a lot like a `std.ArrayList(u8)` but with a cleaner interface and pooling capabilities.

```zig
const StringBuilder = @import("string_builder").StringBuilder;

// Starts off with a static buffer of 100 bytes
// If you go over this, memory will be dynamically allocated 
// It's like calling ensureTotalCapacity on an ArrrayList, but
// those 100 bytes (aka the static portion of the buffer) are 
// re-used when pooling is used

var sb = try new StringBuilder(allocator, 100);

try sb.writeByte('o');
try sb.write('ver 9000!1');
sb.truncate(1);

sb.len();  // 10
sb.string(); // "over 9000!"
```

You can call `sb.writer()` to get an `std.io.Writer`.
```

## Pooling

```zig
const Pool = @import("string_builder").Pool;


// Creates pool of 100 StringBuilders, each configured with a static buffer
// of 10000 bytes
var pool = try Pool.init(allocator, 100, 10000);
var sb = try pool.acquire();
defer pool.release(sb);
```

The `Pool` is thread-safe. The `StringBuilder` is not thread safe.
