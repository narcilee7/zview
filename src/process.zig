//! Process-level metrics: RSS, peak memory.
//! Phase 0: macOS only (uses Mach task_info). Cross-platform coming in Phase 2.

const std = @import("std");
const builtin = @import("builtin");

pub const Snapshot = struct {
    rss_bytes: u64,
    peak_bytes: u64,
};

/// Returns current RSS in bytes (0 if unavailable).
pub fn rssBytes() u64 {
    if (builtin.os.tag != .macos) return 0;
    return machRss() catch 0;
}

pub fn rssKb() i64 {
    return @intCast(rssBytes() / 1024);
}

const mach = @cImport({
    @cInclude("mach/mach.h");
});

fn machRss() !u64 {
    const task = mach.mach_task_self();
    var info: mach.task_vm_info_data_t = undefined;
    var count: mach.mach_msg_type_number_t = @sizeOf(mach.task_vm_info_data_t) / @sizeOf(c_int);
    const kr = mach.task_info(task, mach.TASK_VM_INFO, @ptrCast(&info), &count);
    if (kr != mach.KERN_SUCCESS) return 0;
    return info.phys_footprint;
}
