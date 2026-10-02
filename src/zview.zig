//! zview — Zig-native cross-platform desktop framework.
//!
//! Phase 0.5 (Infra lockdown). See docs/INFRA.md for the locked decisions.
//!
//! Phase 0 MVP scope (macOS only):
//!   • single-process, system WebView (WKWebView)
//!   • comptime-generated dispatch from `pub fn` declarations
//!   • JSON wire protocol (binary protocol deferred to Phase 1, no API change)
//!
//! Usage:
//!   const App = struct {
//!       zview: zview.Config = .{ .title = "Counter", .html = @embedFile("web/index.html") };
//!       count: i64 = 0,
//!
//!       pub fn increment(self: *@This()) i64 { self.count += 1; return self.count; }
//!   };
//!   pub fn main() !void {
//!       var app = App{};
//!       try zview.run(&app);
//!   }
//!
//! Privacy convention (Phase 0): names prefixed with `_` are excluded from the bridge.

const std = @import("std");

pub const bridge = @import("bridge.zig");
pub const runtime = @import("runtime.zig");
pub const Config = @import("app.zig").Config;
pub const process = @import("process.zig");

// Locked in Phase 0.5 — see docs/INFRA.md.
pub const log = @import("log.zig");
pub const errors = @import("errors.zig");
pub const allocators = @import("allocators.zig");
pub const webview = @import("webview.zig");

/// Entry point. Walks the user's app struct at comptime, builds a Bridge, runs.
pub fn run(app_instance: anytype) !void {
    const AppType = @TypeOf(app_instance.*);
    const BridgeType = bridge.Bridge(AppType);
    runtime.run(AppType, BridgeType, app_instance);
}

test "zview module loads" {
    _ = std.testing.refAllDecls(@This());
}
