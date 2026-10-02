//! App config — window geometry, metadata, and HTML payload.
//! This is mixed into user-defined app structs (no inheritance).

const std = @import("std");
const builtin = @import("builtin");

/// Embedded into every zview app as `pub zview: Config`.
/// Inheriting via field (rather than `usingnamespace`) keeps the user's struct
/// as the public type — easier for IDEs and codegen tools to recognize.
pub const Config = struct {
    title: []const u8 = "zview app",
    width: u32 = 720,
    height: u32 = 480,
    html: []const u8 = "",

    /// Platform capability required by this app (Phase 0: macOS only).
    pub fn targetSupported() bool {
        return builtin.os.tag == .macos;
    }
};
