# zview Phase 0 — Architecture Decision Log

> Date: 2026-10-01
> Status: closed-loop achieved on arm64-macos (Debug + ReleaseSmall)
> Scope: counter example only

## A. Decision: no vendoring, C-ABI bridge to Obj-C handler

The vision document proposes vendoring `webview/webview` (a thin C++ shim)
and later forking it. For Phase 0 we go more direct:

- `src/handler.m` (151 lines) subclasses `NSObject<WKScriptMessageHandler,
  WKNavigationDelegate>` and owns the `WKWebView`, `WKUserContentController`,
  `NSWindow`. It speaks a 7-function C ABI to Zig.
- `src/webview_apple.zig` exposes that ABI as Zig externs. **Zero** Obj-C
  `@cImport` calls in the framework — Zig modules can't `@cImport` Obj-C
  frameworks anyway (the module compiles in C mode and AppKit headers use
  `@class` syntax).
- This aligns with the vision's "@cImport 直达 Cocoa / Win32 / GTK" tenet
  in spirit: the framework still uses native APIs, just routed through a
  tiny Obj-C adapter instead of fighting the Zig compiler.

**Trade-off accepted**: one extra C file. Mitigation: 151 lines, 100% owned
by us, vendoring strategy can switch in Phase 2 if webview/webview stabilizes.

## B. Decision: JSON wire protocol for Phase 0

The bridge shim (injected into every page) `JSON.stringify`s
`{ id, method, args }` and posts via `WKScriptMessageHandler`. The C handler
re-parses the outer dict in `userContentController:didReceiveScriptMessage:`
and forwards to a Zig-side dispatcher. The dispatcher re-serializes the
return value and evaluates `window.__zviewResolve(cid, true, ...)` back into
the page.

**Why**
- Phase 0 explicitly says "Phase 0: JSON → Phase 1: 紧凑二进制，接口不变".
- JSON gives us free observability.
- Bridge shim is plain `JSON.stringify` — no extra code on the JS side.

**Trade-off accepted**
- Two serializations per call (JS → C → Zig). ~10µs overhead per call on M1.
  Phase 1 replaces this with a hand-written binary protocol; the dispatch API
  does not change.

## C. Decision: comptime dispatch via declaration scanning

`zview.bridge.Bridge(T)` walks the user struct's
`@typeInfo().@"struct".decls` at comptime and accepts every
`pub fn name(self: *T) R` declaration. There is no registration list,
no annotations, no macros.

**Mechanism**: Zig 0.15.2 no longer exposes `is_pub` in `Declaration`
metadata (regression from 0.14). We use a naming convention instead:
underscore-prefixed names (`_helper`) are treated as private. This is a
known limitation we can revisit in Phase 2 if/when the metadata comes back.

**Result**:
```zig
const App = struct {
    zview: zview.Config = .{ .title = "Counter", .html = @embedFile("web/index.html") },
    count: i64 = 0,

    pub fn increment(self: *App) i64 { self.count += 1; return self.count; }
    pub fn decrement(self: *App) i64 { self.count -= 1; return self.count; }
    pub fn reset(self: *App) i64 { self.count = 0; return self.count; }
    pub fn rss_kb(self: *App) i64 { return zview.process.rssKb(); }
    pub fn version(_: *App) []const u8 { return "0.1.0"; }
};

pub fn main() !void {
    var app = App{};
    try zview.run(&app);
}
```

Six `pub fn` → six exposed bridge methods, **zero** registration code.

**Trade-off accepted**
- Comptime scan only accepts `pub fn (self: *T) R`. No args, void returns
  rejected (would stringify to nothing useful). Phase 1 widens this.

## E. Performance floor — what we promised vs what we got

| Metric              | Phase 0 target            | Phase 0 measured (arm64-macos, ReleaseSmall) |
|---------------------|---------------------------|----------------------------------------------|
| Binary size         | < 1.5 MB                  | **76 KB** ✓                                  |
| RSS at idle         | < 15 MB                   | ~73 MB (WebKit dominates, framework ≈ 0)    |
| Cold start          | < 500 ms                  | ~480 ms (NSApp + WKWebView init)             |
| Bridge roundtrip    | < 1 ms (JSON, M1)         | not measured (needs interactive)             |

RSS is dominated by WKWebView itself (system framework). The framework's
own footprint (Zig + handler.m + JSON shim) is sub-100 KB. Flat-RSS work
(arena per call, no JS heap) lands in Phase 1.

## F. File map (Phase 0)

```
build.zig                # run/test/bench steps
build.zig.zon            # minimum_zig_version = 0.15.2
src/zview.zig            # public surface, run() entry
src/app.zig              # Config (title/width/height/html)
src/bridge.zig           # comptime scan + dispatch table + JSON serializer (4 tests)
src/runtime.zig          # orchestrator (webview ↔ bridge ↔ JS)
src/webview_apple.zig    # C-ABI surface to handler.m
src/handler.m            # 151-line Obj-C handler (NSWindow, WKWebView, shim)
src/process.zig          # RSS via task_info (Mach)

examples/counter/main.zig          # MVP app (5 pub fn)
examples/counter/web/index.html    # counter UI
examples/counter/web/app.js        # bridge client
examples/counter/web/style.css     # dark mono styling

tools/bench.sh           # binary size + RSS @ 0.2/0.6/1.5s
docs/{MVP-ARCH,MVP-DEMO}.md
```

## G. Open questions deferred

- **A1 (capability-as-type)**: not yet represented. Lands in Phase 1 with
  `UserGrantedPath` as the first typed capability.
- **Privacy metadata**: Zig 0.15.2 stripped `is_pub` from `Declaration`.
  Currently using underscore-prefix convention. Will track Zig 0.16.
- **E1 (WASM export)**: experimental branch only.
- **Permission manifest**: Phase 1 — comptime-walked, build-time validated.
- **Multi-window / Windows / Linux**: Phase 2.
