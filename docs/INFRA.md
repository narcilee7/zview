# zview — Infrastructure Lockdown (Phase 0.5)

> Date: 2026-10-02
> Status: lockdown in progress
> Goal: lock the architectural surfaces that are expensive to retrofit
> before Phase 1 features compound on top.

The MVP shipped at commit `d6b5c4c` works, but it leans on a few
"good-enough for now" decisions that will be painful to undo later. This
document captures the four infra items we're locking down now and why.

---

## T1.1 Memory allocator: arena per bridge call (LOCKED)

### Decision
Every bridge dispatch runs inside a fresh `std.heap.ArenaAllocator`. The
arena is reset (or `deinit`'d) at scope exit. The runtime uses the arena
allocator exclusively for per-call scratch (JSON serialization, error
formatting, payload strings). Long-lived allocations (the user app struct,
the WKWebView window, the dispatch table) keep using their original
allocators and never enter the arena.

### Why lock now
- The vision document promises P2 ("Flat RSS 作为可交付特性"). The cheapest
  time to implement that is now, before allocators are scattered.
- Page allocator's per-call malloc/free churn is visible in the Phase 0
  bench: RSS climbs 28 MB → 73 MB in the first 600ms as the bridge
  shim sends several messages. An arena holds the line.
- A retrofitted arena would require touching every `std.heap.page_allocator`
  site — risky and easy to miss.

### Surface
- `src/allocators.zig` exposes `ArenaScope` (RAII wrapper).
- Runtime uses one arena per dispatch. Tests + counter example both work.

---

## T1.2 WebView backend: backend interface locked (LOCKED)

### Decision
A new `src/webview.zig` is the **only** webview import for the runtime.
It compile-time dispatches to one of:

- `src/webview_apple.zig` (Phase 0, macOS WKWebView via `handler.m`)
- `src/webview_stub.zig` (Phase 0+, all other platforms — returns
  `error.PlatformNotSupported` from `run`)

Selection rule:
```zig
pub const Backend = if (builtin.os.tag == .macos)
    @import("webview_apple.zig")
else
    @import("webview_stub.zig");
```

### Why lock now
- Phase 2 will add `webview_linux.zig` (WebKitGTK) and `webview_windows.zig`
  (WebView2). If the runtime already hard-imports `webview_apple`, the
  switchover touches `runtime.zig` + `build.zig` + every example.
- Adding the **stub** now (10 lines, returns a clear error) makes the
  framework compile on Linux/Windows for development. Cheap insurance.

### Surface contract (every backend must implement)
```zig
pub fn runLoopCreate(title: []const u8, width: u32, height: u32, html: []const u8, userdata: *anyopaque, on_msg: MsgFn, on_loaded: ?LoadedFn) *Window;
pub fn runLoopEnter(win: *Window) void;
pub fn evaluate(win: *Window, js: []const u8) void;
pub const Window: type;
```

If Phase 2 backends fail to match this, the compiler catches it.

---

## T1.3 Bridge error protocol (LOCKED)

### Decision
Replace the current stringly-typed error (`@errorName(err)`) with a
typed `BridgeErrorCode` enum. Errors are serialized as a structured object
on the wire:

```json
{
  "ok": false,
  "code": "unknown_method",
  "message": "no such method: nope"
}
```

Success responses stay simple:
```json
1
```
(or whatever JSON value the method returned)

### Why lock now
- Phase 1 needs typed errors per the vision (D2/E1). Implementing it now
  means one protocol, one set of test vectors, one parser on the JS side.
- The current code uses `@errorName(err)` which produces strings like
  `UnknownMethod` (PascalCase). A structured shape is more honest and
  easier to evolve.

### Surface
- `src/errors.zig` defines `BridgeErrorCode` (enum) and `ErrorPayload` (struct).
- `bridge.dispatch` returns `!Payload` where `Payload = union(enum) { value: []const u8, error: ErrorPayload }`.
- Runtime converts to JSON and posts to JS.
- `BRIDGE_SHIM_JS` updated to accept `{ok: true, value}` and
  `{ok: false, code, message}`.

---

## T2.1 Logger (LOCKED)

### Decision
A minimal `src/log.zig` with five levels: `trace`, `debug`, `info`,
`warn`, `err`. Default level is `info`. Configurable via env var
`ZVIEW_LOG=debug` etc. Writes to stderr in `<level> <message>` format.

### Why lock now
- Once Phase 1 adds 10+ commands, scattered `std.debug.print` calls
  become noise. A single logger keeps output consistent.
- Useful for diagnosing production apps the user doesn't have source for.
- ~50 lines, low risk, low cost to retrofit.

### Surface
```zig
pub fn log(level: Level, comptime fmt: []const u8, args: anytype) void;
pub fn trace(comptime fmt: []const u8, args: anytype) void;
// ... debug, info, warn, err
```

Bridge runtime logs each call at `debug` level: `bridge call: method=increment cid=42`.

---

## What's intentionally NOT locked yet

- **Smoke test / CI pipeline** — only worth adding when CI exists.
- **Dev mode vs release mode** — `@embedFile` only for Phase 0; vite
  integration lands with dev-server work in Phase 2.
- **Multi-window** — Phase 2.
- **Linux / Windows webview backends** — Phase 2 (stub covers compile-time).
- **Permission manifest validation (A1 capability-as-type)** — Phase 1,
  but `cap()` declaration API is a separate concern.
- **Release pipeline / notarization / installer** — Phase 3.
- **Documentation site** — Phase 4.

These are all deliberate "not now" decisions, captured here so the next
phase doesn't have to rediscover the trade-off.
