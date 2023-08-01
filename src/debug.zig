const std = @import("std");
const root = @import("root");
const arch = @import("architecture.zig");

pub fn panicDisplay(from_addr: ?u64) void {
    if (from_addr) |addr| {
        root.frameBufferConsole.print("Panic!\nELR: 0x{x:0>8}\n", .{addr}) catch {};
        stackTraceDisplay(addr);
    } else {
        root.frameBufferConsole.print("Panic!\nSource unknown.\n", .{}) catch {};
    }
}

pub fn unknownBreakpointDisplay(from_addr: ?u64, bkpt_number: u16) void {
    if (from_addr) |addr| {
        root.frameBufferConsole.print("Breakpoint\nComment: 0x{x:0>8}\n ELR: 0x{x:0>8}\n", .{ bkpt_number, addr }) catch {};
    } else {
        root.frameBufferConsole.print("Breakpoint\nComment: 0x{x:0>8}\n ELR: unknown\n", .{bkpt_number}) catch {};
    }
}

pub fn unhandledExceptionDisplay(from_addr: ?u64, entry_type: u64, esr: u64, ec: arch.cpu.registers.EC) void {
    if (from_addr) |addr| {
        root.frameBufferConsole.print("Unhandled exception!\nType: 0x{x:0>8}\n ESR: 0x{x:0>8}\n ELR: 0x{x:0>8}\n  EC: {s}\n", .{ entry_type, @as(u64, @bitCast(esr)), addr, @tagName(ec) }) catch {};
    } else {
        root.frameBufferConsole.print("Unhandled exception!\nType: 0x{x:0>8}\n ESR: 0x{x:0>8}\n ELR: unknown\n  EC: 0b{b:0>6}\n", .{ entry_type, esr, @tagName(ec) }) catch {};
    }
}

fn stackTraceDisplay(from_addr: u64) void {
    _ = from_addr;
    var it = std.debug.StackIterator.init(null, null);
    defer it.deinit();

    root.frameBufferConsole.print("\nStack unwind\n", .{}) catch {};
    root.frameBufferConsole.print("Frame\tPC\n", .{}) catch {};
    for (0..40) |i| {
        var addr = it.next() orelse {
            root.frameBufferConsole.print(".\n", .{}) catch {};
            return;
        };
        stackFrameDisplay(i, addr);
    }
    root.frameBufferConsole.print("--stack trace truncated--\n", .{}) catch {};
}

fn stackFrameDisplay(frame_number: usize, frame_pointer: usize) void {
    root.frameBufferConsole.print("{d}\t0x{x:0>8}\n", .{ frame_number, frame_pointer }) catch {};
}
