# zview

> Zig-native cross-platform desktop framework.
> Tauri 的安全架构 × Electron 的壳 API 广度 × Zig 的 comptime 单一真相源。

**Phase 0 — closed loop achieved (2026-10-02).**
**Phase 0.5 — infrastructure lockdown (see docs/INFRA.md).**

## What this is

Single-process + system WebView. The bridge, permission manifest, JS shim
and client types all derive from one comptime-walked `pub fn` declaration.

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

`zig build run` launches a window. A `+` button calls `App.increment`
through the bridge and paints the result. RSS updates every second.

## Try it

```sh
zig build run        # launch the counter
zig build test       # framework unit tests (4 tests, ~4ms)
zig build bench      # binary size + RSS @ 0.2/0.6/1.5s
zig build --help     # list steps
```

Requires Zig **0.15.2** (locked — see `build.zig.zon`).

## Phase 0 measured

| Metric | Target | Actual |
|---|---|---|
| Binary size (ReleaseSmall) | < 1.5 MB | **76 KB** |
| Cold start | < 500 ms | ~480 ms |
| RSS at idle | (will optimize in P1) | ~73 MB (WebKit dominates) |
| Bridge tests | — | 4/4 passing |

## Architecture

See [docs/MVP-ARCH.md](docs/MVP-ARCH.md) for the Phase 0 decision log.
See [docs/MVP-DEMO.md](docs/MVP-DEMO.md) for the counter walk-through.

```
src/zview.zig            public surface, run() entry
src/app.zig               window/HTML config
src/bridge.zig            comptime scan + dispatch table + JSON (4 tests)
src/runtime.zig           orchestrator (webview ↔ bridge ↔ JS)
src/webview_apple.zig     C-ABI surface to handler.m
src/handler.m             151-line Obj-C handler (NSWindow + WKWebView + JS shim)
src/log.zig                 leveled logger (env: ZVIEW_LOG=trace|debug|info|warn|err)
src/errors.zig              typed bridge error protocol (Code enum + JSON payload)
src/allocators.zig          arena-per-call scope (implements P2 flat-RSS)
src/webview.zig             compile-time backend selector
src/webview_stub.zig        stub for non-macOS (returns PlatformNotSupported)
src/process.zig           RSS via Mach task_info
examples/counter/         the MVP app (HTML + Zig + JS + CSS)
tools/bench.sh            Phase 0 benchmark harness
```

## Roadmap (from vision.md)

- **Phase 0** ✅ closed loop, bridge, RSS, bench
- **Phase 1** JSON → compact binary; typed errors; events; first typed capability (`UserGrantedPath`)
- **Phase 2** cross-compile matrix (Win/Linux); shell API (window/dialog/clipboard); dev/release modes
- **Phase 3** `.app` notarization, Windows installer, AppImage, auto-update
- **Phase 4** ecosystem, docs site, WASM export experiment (E1)

## License

MIT — see [LICENSE](LICENSE).
