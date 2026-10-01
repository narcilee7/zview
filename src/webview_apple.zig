//! macOS WKWebView bindings via a thin C ABI (src/handler.m).
//!
//! All Cocoa/AppKit/WebKit interaction is hidden inside src/handler.m so that
//! this Zig module never has to @cImport Objective-C frameworks directly —
//! those imports don't work because Zig modules compile in C mode.

const std = @import("std");

// ─── Opaque C-side window state ───────────────────────────────────────────────
pub const Window = opaque {};

// ─── ABI from src/handler.m ──────────────────────────────────────────────────

extern fn zview_create(
    userdata: *anyopaque,
    on_msg: *const fn (userdata: *anyopaque, method: [*:0]const u8, payload: [*:0]const u8, cid: u64) callconv(.c) void,
    on_loaded: ?*const fn (userdata: *anyopaque) callconv(.c) void,
    title: [*:0]const u8,
    width: f64,
    height: f64,
    html: [*:0]const u8,
) ?*Window;
extern fn zview_run_loop() void;
extern fn zview_evaluate(win: *Window, js: [*:0]const u8) void;
extern fn zview_destroy(win: *Window) void;

// ─── Public surface ──────────────────────────────────────────────────────────

/// Create the WKWebView + NSWindow, register the script message handler.
/// Returns the opaque window pointer the runtime needs for JS evaluation.
pub fn runLoopCreate(
    title: []const u8,
    width: u32,
    height: u32,
    html: []const u8,
    userdata: *anyopaque,
    on_message: *const fn (userdata: *anyopaque, method: [*:0]const u8, payload: [*:0]const u8, cid: u64) callconv(.c) void,
    on_loaded: ?*const fn (userdata: *anyopaque) callconv(.c) void,
) *Window {
    return zview_create(
        userdata,
        on_message,
        on_loaded,
        @as([*:0]const u8, @ptrCast(title.ptr)),
        @as(f64, @floatFromInt(width)),
        @as(f64, @floatFromInt(height)),
        @as([*:0]const u8, @ptrCast(html.ptr)),
    ) orelse @panic("zview: zview_create returned null");
}

pub fn runLoopEnter(win: *Window) void {
    zview_run_loop();
    zview_destroy(win);
}

/// Evaluate JS in the main frame.
pub fn evaluate(win: *Window, js: []const u8) void {
    zview_evaluate(win, @as([*:0]const u8, @ptrCast(js.ptr)));
}
