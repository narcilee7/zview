//! Runtime orchestrator. Sets up the webview loop and threads bridge dispatch.
//!
//! Phase 0.5 lockdown: arena-per-call, typed errors, structured logging.

const std = @import("std");
const webview = @import("webview.zig");
const bridge = @import("bridge.zig");
const allocators = @import("allocators.zig");
const errors = @import("errors.zig");
const log = @import("log.zig");

/// Enters the macOS NSApplication run loop with the given bridge.
/// Blocks until the user closes the window.
pub fn run(
    comptime AppType: type,
    comptime BridgeType: type,
    app: *AppType,
) void {
    const Payload = struct {
            app: *AppType,
            win: *webview.Window,
        };
    var win: *webview.Window = undefined;
    var payload = Payload{ .app = app, .win = undefined };

    const dispatchFn = struct {
        fn call(ctx_void: *anyopaque, method: [*:0]const u8, payload_bytes: [*:0]const u8, cid: u64) callconv(.c) void {
            const p: *Payload = @ptrCast(@alignCast(ctx_void));
            onMessage(BridgeType, p, std.mem.sliceTo(method, 0), std.mem.sliceTo(payload_bytes, 0), cid);
        }
    }.call;

    win = webview.runLoopCreate(
        app.zview.title,
        app.zview.width,
        app.zview.height,
        app.zview.html,
        @ptrCast(&payload),
        dispatchFn,
        null,
    );
    payload.win = win;

    log.info("zview: webview window created ({s}, {d}x{d})", .{ app.zview.title, app.zview.width, app.zview.height });

    webview.runLoopEnter(win);
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

    // Arena scope — all scratch allocations (JSON buffers, error payloads)
    // die at function exit. Implements the vision's flat-RSS promise.
    var scope = allocators.DispatchScope.init(std.heap.page_allocator);
    defer scope.deinit();

    log.debug("bridge call: method={s} cid={d}", .{ method, cid });

    const result = BridgeType.dispatch(payload.app, method);

    // We write into a fixed stack buffer (typical response is <1 KB) to avoid
    // coupling the response lifetime to the arena's deinit.
    var resp_buf: [8192]u8 = undefined;
    var resp_w = std.io.Writer.fixed(&resp_buf);

    switch (result) {
        .value => |value| {
            // success: __zviewResolve(cid, true, <value>)
            resp_w.print("window.__zviewResolve({d}, true, {s});", .{ cid, value }) catch {
                writeErrorResponse(win, cid, errors.Payload{
                    .code = .serialize_error,
                    .message = "response too large",
                });
                return;
            };
            const js = resp_buf[0..resp_w.end];
            log.trace("bridge response: cid={d} ok value_len={d}", .{ cid, value.len });
            webview.evaluate(win, js);
        },
        .err => |err_payload| {
            writeErrorResponse(win, cid, err_payload);
        },
    }
}

fn writeErrorResponse(win: *webview.Window, cid: u64, payload: errors.Payload) void {
    var resp_buf: [1024]u8 = undefined;
    var resp_w = std.io.Writer.fixed(&resp_buf);
    resp_w.print("window.__zviewResolve({d}, false, ", .{cid}) catch return;
    payload.writeJson(&resp_w) catch return;
    resp_w.writeAll(");") catch return;

    const js = resp_buf[0..resp_w.end];
    log.debug("bridge error: cid={d} code={s} msg={s}", .{ cid, @tagName(payload.code), payload.message });
    webview.evaluate(win, js);
}
