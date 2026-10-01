//! Compile-time dispatch to the active WebView backend.
//!
//! Locked in Phase 0.5 (see docs/INFRA.md §T1.2). Phase 2 will add
//! `webview_linux.zig` (WebKitGTK) and `webview_windows.zig` (WebView2);
//! both must match the surface here.

const std = @import("std");
const builtin = @import("builtin");

/// The active backend. Runtime imports *only* this — never webview_apple
/// or webview_stub directly.
const Backend = if (builtin.os.tag == .macos)
    @import("webview_apple.zig")
else
    @import("webview_stub.zig");

pub const Window = Backend.Window;
pub const runLoopCreate = Backend.runLoopCreate;
pub const runLoopEnter = Backend.runLoopEnter;
pub const evaluate = Backend.evaluate;

test "webview: backend module compiles" {
    _ = std.testing.refAllDecls(@This());
}
