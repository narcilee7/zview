const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ─── zview core library ──────────────────────────────────────────────
    const lib_mod = b.addModule("zview", .{
        .root_source_file = b.path("src/zview.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.link_libc = true;
    linkAppleFrameworks(lib_mod);

    // ─── Framework unit tests (no webview, no example code) ───────────────
    const lib_tests = b.addTest(.{
        .name = "zview-tests",
        .root_module = lib_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run framework unit tests");
    test_step.dependOn(&run_lib_tests.step);

    // ─── examples (comptime-known list) ──────────────────────────────────
    inline for (.{ExampleCfg{ .name = "counter", .root = "examples/counter/main.zig" }}) |cfg| {
        const exe = b.addExecutable(.{
            .name = cfg.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(cfg.root),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zview", .module = lib_mod },
                },
            }),
        });
        exe.linkLibC();
        linkAppleFrameworks(exe.root_module);
        exe.root_module.addCSourceFile(.{
            .file = b.path("src/handler.m"),
            .flags = &.{ "-fobjc-arc" },
            .language = .objective_c,
        });

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step("run-" ++ cfg.name, "Run " ++ cfg.name ++ " example");
        run_step.dependOn(&run_cmd.step);

        if (std.mem.eql(u8, cfg.name, "counter")) {
            const default_run = b.step("run", "Run the counter MVP example");
            default_run.dependOn(&run_cmd.step);
        }
    }

    // ─── bench step ──────────────────────────────────────────────────────
    const bench_step = b.step("bench", "Benchmark RSS / startup / binary size");
    bench_step.dependOn(b.getInstallStep());
    const bench_run = b.addSystemCommand(&.{ "sh", "tools/bench.sh" });
    bench_step.dependOn(&bench_run.step);
}

fn linkAppleFrameworks(mod: *std.Build.Module) void {
    if (mod.resolved_target.?.result.os.tag == .macos) {
        mod.linkFramework("Foundation", .{});
        mod.linkFramework("AppKit", .{});
        mod.linkFramework("WebKit", .{});
        mod.linkFramework("CoreFoundation", .{});
    }
}

const ExampleCfg = struct {
    name: []const u8,
    root: []const u8,
};
