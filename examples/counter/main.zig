//! zview Counter MVP — Phase 0 closed-loop example.
//!
//! Demonstrates:
//!   • comptime bridge discovery (5 pub fn declarations)
//!   • JSON wire protocol over window.webkit.messageHandlers
//!   • single-process WKWebView with @embedFile frontend assets
//!   • live RSS measurement in the UI
//!
//! Run: zig build run

const std = @import("std");
const zview = @import("zview");

const App = struct {
    zview: zview.Config = .{
        .title = "zview Counter",
        .width = 520,
        .height = 360,
        .html = @embedFile("web/index.html"),
    },

    count: i64 = 0,

    pub fn increment(self: *App) i64 {
        self.count += 1;
        return self.count;
    }

    pub fn decrement(self: *App) i64 {
        self.count -= 1;
        return self.count;
    }

    pub fn get(self: *App) i64 {
        return self.count;
    }

    pub fn reset(self: *App) i64 {
        self.count = 0;
        return self.count;
    }

    pub fn rss_kb(self: *App) i64 {
        _ = self;
        return zview.process.rssKb();
    }

    pub fn version(_: *App) []const u8 {
        return "0.1.0";
    }
};

pub fn main() !void {
    var app = App{};
    try zview.run(&app);
}
