# zview Counter — MVP demo

Phase 0 closed-loop demonstration of the zview framework. Pressing +/− in
the window calls a Zig function through the in-process WKWebView bridge and
the return value paints back into the UI. RSS updates every second.

## Run

```sh
zig build run
```

That's it. A window titled **zview Counter** appears.

## What you should see

- `0` in large mono digits.
- `RSS — kB` chip in the top-right (updates every 1s).
- `→ method` flashes in the subheader while a button is pressed.
- Click `+` → count goes up. Click `−` → count goes down. Click `reset` → 0.
- Click `version` → footer reads `zview 0.1.0 · zig 0.15.2 · WKWebView · JSON bridge`.

## How the loop closes

```
[ click + ]
   │
   ▼
window.__zview.call('increment')           (web/app.js)
   │
   ▼
window.webkit.messageHandlers.zview
   .postMessage(JSON.stringify({id,method:'increment',args:[]}))
   │  (BRIDGE_SHIM_JS, injected at document-start via WKUserScript)
   ▼
[WKUserContentController → ZviewHandler]    (src/handler.m)
   │  didReceiveScriptMessage: parses JSON, forwards to on_msg
   ▼
on_message(ctx, 'increment', '[]', 1)      (function pointer into Zig)
   │
   ▼
BridgeType.dispatch(app, 'increment')      (src/bridge.zig, comptime)
   │  comptime-resolved at build time → function pointer
   ▼
app.increment(&app)                        (examples/counter/main.zig)
   │
   ▼
JSON.stringify(return) → "1"               (std.json.Stringify)
   │
   ▼
[zview_evaluate → gWebView evaluateJavaScript:]   (src/handler.m)
   │
   ▼
window.__zviewResolve(1, true, 1)          (BRIDGE_SHIM_JS)
   │
   ▼
pending.get(1).resolve(1)  →  setCount(1)   (web/app.js)
```

## Bench

```sh
zig build bench
```

Output goes to `zig-out/bench.log`. Phase 0 measured (arm64-macos,
ReleaseSmall):

```
binary size: 76 KB (78664 bytes)
cold start (sample RSS over time):
  t= 211ms  RSS=28192 KB
  t= 626ms  RSS=73392 KB
  t=1546ms  RSS=74064 KB
```

## Tests

```sh
zig build test
```

4 unit tests cover the comptime bridge generation, JSON serialization,
return-value type dispatch (i64, f64, []const u8, bool), and the unknown-
method error path. They run in ~4ms.

## What's NOT in Phase 0

- Multiple windows (single window only)
- File system / dialog / clipboard APIs (shell layer is empty)
- Dev / release mode distinction (only `@embedFile` mode)
- Permission manifest validation
- Cross-platform (macOS only — Phase 2 adds Windows + Linux)
- Auto-update, code signing, packaging
