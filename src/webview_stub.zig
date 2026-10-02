//! Stub backend for non-macOS platforms.
//!
//! Phase 0 supports macOS only. On other platforms, the framework still
//! *compiles* so cross-platform development works; `runLoopCreate` returns
//! an error at runtime.

const std = @import("std");
const builtin = @import("builtin");

pub const Window = opaque {};

pub fn runLoopCreate(
    title: []const u8,
    width: u32,
    height: u32,
    html: []const u8,
    userdata: *anyopaque,
    on_message: *const fn (userdata: *anyopaque, method: [*:0]const u8, payload: [*:0]const u8, cid: u64) callconv(.c) void,
    on_loaded: ?*const fn (userdata: *anyopaque) callconv(.c) void,
) *Window {
    _ = title;
    _ = width;
    _ = height;
    _ = html;
    _ = userdata;
    _ = on_message;
    _ = on_loaded;
    std.debug.print(
        "zview: Phase 0 supports macOS only (got os={s}). See docs/INFRA.md §T1.2.\n",
            .{@tagName(builtin.os.tag)},
        );
    std.process.exit(1);
}

pub fn runLoopEnter(_: *Window) void {}

pub fn evaluate(_: *Window, _: []const u8) void {}
