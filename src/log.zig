//! zview logger. Five levels, stderr, env-configurable via ZVIEW_LOG=trace|debug|info|warn|err.
//!
//! Usage:
//!     const log = @import("log");
//!     log.debug("bridge call: method={s} cid={d}", .{ method, cid });
//!
//! Locked in Phase 0.5. New code should use this instead of `std.debug.print`.

const std = @import("std");

pub const Level = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,
};

var g_level: Level = .info;
var g_inited: bool = false;

fn ensureInit() void {
    if (g_inited) return;
    g_inited = true;
    const s = std.posix.getenv("ZVIEW_LOG") orelse return;
    if (std.ascii.eqlIgnoreCase(s, "trace")) g_level = .trace
    else if (std.ascii.eqlIgnoreCase(s, "debug")) g_level = .debug
    else if (std.ascii.eqlIgnoreCase(s, "info")) g_level = .info
    else if (std.ascii.eqlIgnoreCase(s, "warn")) g_level = .warn
    else if (std.ascii.eqlIgnoreCase(s, "err")) g_level = .err
    ;
}

/// Test-only: override the level (e.g. to silence test output).
pub fn setLevelForTesting(l: Level) void {
    g_level = l;
    g_inited = true;
}

fn parseLevelBytes(s: []const u8) ?Level {
    inline for (@typeInfo(Level).@"enum".fields) |f| {
        if (std.ascii.eqlIgnoreCase(s, f.name)) return @enumFromInt(f.value);
    }
    return null;
}

pub fn logAt(level: Level, comptime fmt: []const u8, args: anytype) void {
    ensureInit();
    if (@intFromEnum(level) < @intFromEnum(g_level)) return;
    const file = std.fs.File.stderr();
    var buf: [4096]u8 = undefined;
    var w = file.writer(&buf);
    defer _ = w.interface.flush() catch {};
    w.interface.print("[{s}] " ++ fmt ++ "\n", .{@tagName(level)} ++ args) catch return;
}

pub fn trace(comptime fmt: []const u8, args: anytype) void { logAt(.trace, fmt, args); }
pub fn trace_(comptime fmt: []const u8, args: anytype) void { logAt(.trace, fmt, args); }
pub fn debug(comptime fmt: []const u8, args: anytype) void { logAt(.debug, fmt, args); }
pub fn info(comptime fmt: []const u8, args: anytype) void { logAt(.info, fmt, args); }
pub fn warn(comptime fmt: []const u8, args: anytype) void { logAt(.warn, fmt, args); }
pub fn err_(comptime fmt: []const u8, args: anytype) void { logAt(.err, fmt, args); }

test "log: level filtering" {
    setLevelForTesting(.warn);
    // Lower than warn → not asserted; we just verify no crash.
    trace_("ignored {d}", .{1});
    debug("ignored {d}", .{2});
    info("ignored {d}", .{3});
    warn("emitted {d}", .{4});
    err_("emitted {d}", .{5});
}

test "log: parseLevel" {
    try std.testing.expectEqual(@as(?Level, .debug), parseLevelBytes("debug"));
    try std.testing.expectEqual(@as(?Level, .debug), parseLevelBytes("DEBUG"));
    try std.testing.expectEqual(@as(?Level, .err), parseLevelBytes("err"));
    try std.testing.expectEqual(@as(?Level, null), parseLevelBytes("nope"));
}
