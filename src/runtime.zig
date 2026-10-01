//! Runtime orchestrator. Sets up the webview loop and threads bridge dispatch.

const std = @import("std");
const webview_apple = @import("webview_apple.zig");
const bridge = @import("bridge.zig");

/// Enters the macOS NSApplication run loop with the given bridge.
/// Blocks until the user closes the window.
pub fn run(
    comptime AppType: type,
    comptime BridgeType: type,
    app: *AppType,
) void {
    const Payload = struct {
            app: *AppType,
            win: *webview_apple.Window,
        };
    var win: *webview_apple.Window = undefined;
    var payload = Payload{ .app = app, .win = undefined };

    const dispatchFn = struct {
        fn call(ctx_void: *anyopaque, method: [*:0]const u8, payload_bytes: [*:0]const u8, cid: u64) callconv(.c) void {
            const p: *Payload = @ptrCast(@alignCast(ctx_void));
            onMessage(BridgeType, p, std.mem.sliceTo(method, 0), std.mem.sliceTo(payload_bytes, 0), cid);
        }
    }.call;

    win = webview_apple.runLoopCreate(
        app.zview.title,
        app.zview.width,
        app.zview.height,
        app.zview.html,
        @ptrCast(&payload),
        dispatchFn,
        null,
    );
    payload.win = win;

    webview_apple.runLoopEnter(win);
}

fn onMessage(
    comptime BridgeType: type,
    payload: anytype,
    method: []const u8,
    payload_bytes: []const u8,
    cid: u64,
) void {
    _ = payload_bytes;
    const win = payload.win;
    const result_str = BridgeType.dispatch(payload.app, method) catch |err| {
        const err_msg = @errorName(err);
        const buf = std.fmt.allocPrint(std.heap.page_allocator, "window.__zviewResolve({d}, false, \"{s}\");", .{ cid, err_msg }) catch return;
        defer std.heap.page_allocator.free(buf);
        webview_apple.evaluate(win, buf);
        return;
    };

    const buf = std.fmt.allocPrint(std.heap.page_allocator, "window.__zviewResolve({d}, true, {s});", .{ cid, result_str }) catch {
        const err_buf = std.fmt.allocPrint(std.heap.page_allocator, "window.__zviewResolve({d}, false, \"serialize error\");", .{cid}) catch return;
        defer std.heap.page_allocator.free(err_buf);
        webview_apple.evaluate(win, err_buf);
        return;
    };
    defer std.heap.page_allocator.free(buf);
    webview_apple.evaluate(win, buf);
}
