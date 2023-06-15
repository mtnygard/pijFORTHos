pub const registers = @import("aarch64/registers.zig");
pub const time = @import("aarch64/time.zig");

/// Note: this performs an "exception return" on the CPU. It will
/// change the stack point and exception level, meaning that this does
/// not return to the call site.
pub inline fn eret() void {
    asm volatile ("eret");
}
