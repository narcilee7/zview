//! Bridge layer — JSON dispatch from JS → Zig, with comptime-generated table.
//! Phase 0 protocol: JSON in, JSON out. Phase 1 swaps to compact binary, no API change.

const std = @import("std");

const Decl = std.builtin.Type.Declaration;

/// Comptime predicate: does `decl` describe a bridgeable method on T?
fn isBridgeableMethod(comptime T: type, decl: Decl) bool {
    if (decl.name.len > 0 and decl.name[0] == '_') return false;
    if (std.mem.eql(u8, decl.name, "zview")) return false;
    if (!@hasDecl(T, decl.name)) return false;
    const decl_val = @field(T, decl.name);
    const ti = @typeInfo(@TypeOf(decl_val));
    if (ti != .@"fn") return false;
    const fn_info = ti.@"fn";
    if (fn_info.params.len != 1) return false;
    if (fn_info.return_type == null) return false;
    const ret_type = fn_info.return_type.?;
    if (ret_type == void) return false;
    const param_type = fn_info.params[0].type.?;
    const pointee_info = @typeInfo(param_type);
    if (pointee_info != .pointer) return false;
    if (pointee_info.pointer.size != .one) return false;
    if (pointee_info.pointer.child != T) return false;
    return true;
}

/// One entry in the comptime-generated dispatch table.
pub const Entry = struct {
    name: []const u8,
    invoke: *const fn (app: *anyopaque) []const u8,
};

pub fn Bridge(comptime T: type) type {
    const info = @typeInfo(T).@"struct";

    comptime var method_count: usize = 0;
    inline for (info.decls) |decl| {
        if (isBridgeableMethod(T, decl)) method_count += 1;
    }

    const Entries = buildEntries(T, method_count);

    return struct {
        pub const AppType = T;
        pub const entries: []const Entry = &Entries;

        pub fn dispatch(app: *T, method: []const u8) ![]const u8 {
            for (entries) |e| {
                if (std.mem.eql(u8, e.name, method)) {
                    return e.invoke(app);
                }
            }
            return error.UnknownMethod;
        }

        pub fn has(method: []const u8) bool {
            for (entries) |e| {
                if (std.mem.eql(u8, e.name, method)) return true;
            }
            return false;
        }

        pub fn count() usize {
            return entries.len;
        }
    };
}

fn buildEntries(comptime T: type, comptime N: usize) [N]Entry {
    var buf: [N]Entry = undefined;
    const info = @typeInfo(T).@"struct";
    var idx: usize = 0;
    inline for (info.decls) |decl| {
        if (!isBridgeableMethod(T, decl)) continue;
        const fn_val = @field(T, decl.name);
        const Helper = struct {
            fn invoke_typed(app: *anyopaque) []const u8 {
                const real: *T = @ptrCast(@alignCast(app));
                const value = @call(.auto, fn_val, .{real});
                return serializeValue(@TypeOf(value), value) catch "null";
            }
        };
        buf[idx] = .{
            .name = decl.name,
            .invoke = &Helper.invoke_typed,
        };
        idx += 1;
    }
    return buf;
}

/// Serialize a JSON value into a stack buffer. Returns "" on overflow.
pub fn serializeValue(comptime T: type, value: T) ![]const u8 {
    var buf: [4096]u8 = undefined;
    var w = std.io.Writer.fixed(&buf);
    try std.json.Stringify.value(value, .{}, &w);
    return buf[0..w.end];
}

pub const Response = union(enum) {
    ok: []const u8,
    err: []const u8,
};

// ─── Tests ──────────────────────────────────────────────────────────────────

test "Bridge: comptime discovers 3 methods on a sample app" {
    const Sample = struct {
        count: i64 = 0,

        pub fn inc(self: *@This()) i64 {
            self.count += 1;
            return self.count;
        }
        pub fn dec(self: *@This()) i64 {
            self.count -= 1;
            return self.count;
        }
        pub fn get(self: *@This()) i64 {
            return self.count;
        }
        // Private — underscore-prefix means skip
        fn _internal(_: *@This()) i64 {
            return -1;
        }
        // Wrong signature — must be skipped
        pub fn wrong(_: i64) i64 {
            return 0;
        }
    };

    const B = Bridge(Sample);
    try std.testing.expectEqual(@as(usize, 3), B.count());
    try std.testing.expect(B.has("inc"));
    try std.testing.expect(B.has("dec"));
    try std.testing.expect(B.has("get"));
    try std.testing.expect(!B.has("_internal"));
    try std.testing.expect(!B.has("wrong"));
}

test "Bridge: dispatch returns JSON-serialized value" {
    const Sample = struct {
        count: i64 = 0,

        pub fn inc(self: *@This()) i64 {
            self.count += 1;
            return self.count;
        }
        pub fn reset(self: *@This()) i64 {
            self.count = 0;
            return self.count;
        }
    };

    var s = Sample{};
    const B = Bridge(Sample);

    try std.testing.expectEqualStrings("1", try B.dispatch(&s, "inc"));
    try std.testing.expectEqualStrings("2", try B.dispatch(&s, "inc"));
    try std.testing.expectEqualStrings("0", try B.dispatch(&s, "reset"));
    try std.testing.expectEqualStrings("1", try B.dispatch(&s, "inc"));

    try std.testing.expectError(error.UnknownMethod, B.dispatch(&s, "nope"));
}

test "Bridge: handles string and float return values" {
    const Sample = struct {
        pub fn name(_: *@This()) []const u8 {
            return "zview";
        }
        pub fn pi(_: *@This()) f64 {
            return 3.14159;
        }
        pub fn truth(_: *@This()) bool {
            return true;
        }
    };

    var s = Sample{};
    const B = Bridge(Sample);

    try std.testing.expectEqualStrings("\"zview\"", try B.dispatch(&s, "name"));
    try std.testing.expectEqualStrings("3.14159", try B.dispatch(&s, "pi"));
    try std.testing.expectEqualStrings("true", try B.dispatch(&s, "truth"));
}

