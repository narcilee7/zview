//! Bridge error protocol.
//!
//! On the wire, an error response is:
//!     { "ok": false, "code": "<enum_tag>", "message": "<human-readable>" }
//!
//! A success response is the JSON-serialized return value (e.g. `42` or
//! `"0.1.0"`).
//!
//! Phase 0.5 lockdown. The enum is stable; new codes go at the end.
//! JS clients should branch on `code`, never on `message`.

const std = @import("std");

pub const Code = enum {
    /// The named method was not found on the app struct.
    unknown_method,
    /// Method exists but signature did not validate. Phase 1+ only.
    invalid_args,
    /// Bridge dispatcher could not JSON-serialize the return value.
    serialize_error,
    /// Catch-all for unexpected runtime errors.
    internal_error,
    /// WebView backend does not support this platform (e.g. Linux in Phase 0).
    platform_not_supported,
};

/// Wire-level error payload. Serialized as JSON object.
pub const Payload = struct {
    code: Code,
    message: []const u8,

    /// Serialize to a JSON object. Uses a fixed-size buffer (typical error
    /// messages are short). For very long messages, callers should pre-truncate.
    pub fn writeJson(self: Payload, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll("{\"ok\":false,\"code\":\"");
        try writer.writeAll(@tagName(self.code));
        try writer.writeAll("\",\"message\":\"");
        try self.writeEscaped(writer);
        try writer.writeAll("\"}");
    }

    fn writeEscaped(self: Payload, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        // Minimal JSON string escaper for the chars that matter in error msgs.
        var idx: usize = 0;
        while (idx < self.message.len) : (idx += 1) {
            const c = self.message[idx];
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(c),
            }
        }
    }
};

/// Construct an error payload from a Zig error and a context string.
pub fn fromError(err: anyerror, fallback_msg: []const u8) Payload {
    const code: Code = if (err == error.UnknownMethod)
        .unknown_method
    else if (err == error.SerializeError)
        .serialize_error
    else
        .internal_error;
    return .{ .code = code, .message = fallback_msg };
}

test "Payload: writeJson produces wire-compatible JSON" {
    var buf: [256]u8 = undefined;
    var w = std.io.Writer.fixed(&buf);
    const p = Payload{ .code = .unknown_method, .message = "no such method: foo" };
    try p.writeJson(&w);
    try std.testing.expectEqualStrings(
        \\{"ok":false,"code":"unknown_method","message":"no such method: foo"}
    , buf[0..w.end]);
}

test "Payload: messages with quotes are escaped" {
    var buf: [256]u8 = undefined;
    var w = std.io.Writer.fixed(&buf);
    const p = Payload{ .code = .internal_error, .message = "bad: \"x\"" };
    try p.writeJson(&w);
    const out = buf[0..w.end];
    try std.testing.expect(std.mem.indexOf(u8, out, "\\\"x\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"ok\":false") != null);
}

test "Payload: fromError maps UnknownMethod correctly" {
    const p = fromError(error.UnknownMethod, "nope");
    try std.testing.expectEqual(Code.unknown_method, p.code);
    try std.testing.expectEqualStrings("nope", p.message);
}
