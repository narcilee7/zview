//! Per-dispatch arena allocator.
//!
//! The bridge runtime creates one `DispatchScope` per incoming JS message.
//! All scratch allocations (JSON buffers, error payloads) use the scope's
//! arena allocator. The arena is reset when the scope goes out of scope.
//!
//! This implements the vision document's P2 promise ("Flat RSS 作为可交付特性")
//! at the framework level: per-call allocations return to the OS instead of
//! accumulating as heap fragmentation.
//!
//! Phase 0.5 lockdown. Do not bypass.

const std = @import("std");

/// Owns one ArenaAllocator. `deinit()` releases all per-call memory.
pub const DispatchScope = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(parent: std.mem.Allocator) DispatchScope {
        return .{ .arena = std.heap.ArenaAllocator.init(parent) };
    }

    pub fn allocator(self: *DispatchScope) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Total bytes currently held by the arena. Useful for instrumentation.
    pub fn totalBytes(self: *DispatchScope) usize {
        return self.arena.queryCapacity();
    }

    pub fn deinit(self: *DispatchScope) void {
        self.arena.deinit();
    }
};

test "DispatchScope: alloc then deinit returns memory to parent" {
    var scope = DispatchScope.init(std.testing.allocator);
    defer scope.deinit();
    const alloc = scope.allocator();

    const slice = try alloc.alloc(u8, 1024);
    try std.testing.expectEqual(@as(usize, 1024), slice.len);

    // Note: capacity is sticky inside the arena; we don't assert dealloc.
    // The point of the test is that deinit() doesn't leak.
}
