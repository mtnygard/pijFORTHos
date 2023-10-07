const std = @import("std");
const arch = @import("architecture.zig");
const hal = @import("hal.zig");
const qemu = @import("qemu.zig");
const heap = @import("heap.zig");
const frame_buffer = @import("frame_buffer.zig");
const fbcons = @import("fbcons.zig");
const bcd = @import("bcd.zig");
const forty = @import("forty/forth.zig");
const Forth = forty.Forth;
const raspi3 = @import("hal/raspi3.zig");

pub const debug = @import("debug.zig");
pub const devicetree = @import("devicetree.zig");

pub const kinfo = debug.kinfo;
pub const kwarn = debug.kwarn;
pub const kerror = debug.kerror;
pub const kprint = debug.kprint;

const Freestanding = struct {
    page_allocator: std.mem.Allocator,
};

var os = Freestanding{
    .page_allocator = undefined,
};

pub var board = hal.common.BoardInfo{};
pub var kernel_heap = heap{};
pub var fb: frame_buffer.FrameBuffer = frame_buffer.FrameBuffer{};
pub var frame_buffer_console: fbcons.FrameBufferConsole = fbcons.FrameBufferConsole{ .fb = &fb };
pub var interpreter: Forth = Forth{};
pub var global_unwind_point = arch.cpu.exceptions.UnwindPoint{
    .sp = undefined,
    .pc = undefined,
    .fp = undefined,
    .lr = undefined,
};

pub var uart_valid = false;
pub var console_valid = false;

fn recursivePrint(a: i64, x: [798]usize, b: i64, c: i64) [798]usize {
    var ret: [798]usize = undefined;
    for (0..ret.len) |k| {
        ret[k] = k + x[k];
    }

    const q = @divTrunc(44, 7);

    if (a <= 0 or q > 1000000) {
        //        _ = hal.serial.puts("a is zero, all done\n\n");
        _ = raspi3.pl011_uart.stringSend("a is zero, all done\n\n");
        return ret;
    } else if (b != (a + 7)) {
        //        _ = hal.serial.puts("b is not a + 7\n");
        _ = raspi3.pl011_uart.stringSend("b is not a + 7\n");
    } else if (c != (a - 9)) {
        //        _ = hal.serial.puts("c is not a - 9\n");
        _ = raspi3.pl011_uart.stringSend("c is not a - 9\n");
    }

    const seed = a - 1;
    const result = recursivePrint(seed - 1, x, seed - 1 + 7, seed - 1 - 9);

    if (result.len != 798) {
        //        _ = hal.serial.puts("result len is not right\n\n");
        _ = raspi3.pl011_uart.stringSend("result len is not right\n\n");
    }
    for (0..result.len) |k| {
        if (result[k] != x[k] + k) {
            //            _ = hal.serial.puts("result array is not right\n\n");
            _ = raspi3.pl011_uart.stringSend("result array is not right\n\n");
        }
    }
    return ret;
}

fn kernelInit() void {
    // State: one core, no interrupts, no MMU, no heap Allocator, no display, no serial
    arch.cpu.mmu.init();

    kernel_heap.init(raspi3.device_start - 1);
    os.page_allocator = kernel_heap.allocator();

    devicetree.init();

    hal.init(devicetree.root_node, &os.page_allocator) catch {
        //        hal.serial_writer.print("Early init error. Cannot proceed.", .{}) catch {};
    };

    // State: one core, no interrupts, MMU, heap Allocator, no display, no serial
    arch.cpu.exceptions.init(hal.irq_thunk);

    // State: one core, interrupts, MMU, heap Allocator, no display, no serial
    uart_valid = true;

    var data: [798]usize = undefined;
    for (0..data.len) |ii| {
        data[ii] = @intCast(ii);
    }

    while (true) {
        //        hal.serial_writer.print("top of while loop {}\n", .{55}) catch {};
        //        _ = hal.serial.puts("top of while loop\n");
        _ = raspi3.pl011_uart.stringSend("top of while loop\n");
        for (1..5) |i| {
            const j: i64 = @intCast(i % 9);
            _ = recursivePrint(j, data, j + 7, j - 9);
        }
        //        _ = hal.serial.puts("bottom of while loop\n");
        _ = raspi3.pl011_uart.stringSend("bottom of while loop\n");
    }

    unreachable;
}

fn printOneDot(_: ?*anyopaque) u32 {
    frame_buffer_console.emit('%');
    return 300000;
}

fn repl() callconv(.C) noreturn {
    while (true) {
        interpreter.repl() catch |err| {
            kerror(@src(), "REPL error: {any}\n\nABORT.\n", .{err});
        };
    }
}

// TODO do we need both of these now?

fn supplyAddress(name: []const u8, addr: usize) void {
    interpreter.defineConstant(name, addr) catch |err| {
        kwarn(@src(), "Failed to define {s}: {any}\n", .{ name, err });
    };
}

fn supplyUsize(name: []const u8, sz: usize) void {
    interpreter.defineConstant(name, sz) catch |err| {
        kwarn(@src(), "Failed to define {s}: {any}\n", .{ name, err });
    };
}

fn diagnostics() !void {
    for (board.memory.regions.items) |r| {
        try r.print();
    }
    try kernel_heap.range.print();
    try fb.range.print();
}

export fn _start_zig(phys_boot_core_stack_end_exclusive: u64) noreturn {
    const registers = arch.cpu.registers;

    registers.sctlr_el1.write(.{
        .mmu_enable = .disable,
        .a = .disable,
        .sa = 0,
        .sa0 = 0,
        .naa = .trap_disable,
        .ee = .little_endian,
        .e0e = .little_endian,
        .i_cache = .disabled,
        .d_cache = .disabled,
        .wxn = 0,
    });

    // this is harmless at the moment, but it lets me get the code
    // infrastructure in place to make the EL2 -> EL1 transition
    registers.cnthctl_el2.modify(.{
        .el1pcen = .trap_disable,
        .el1pcten = .trap_disable,
    });

    // Zig and LLVM like to use vector registers. Must not trap on the
    // SIMD/FPE instructions for that to work.
    registers.cpacr_el1.write(.{
        .zen = .trap_none,
        .fpen = .trap_none,
        .tta = .trap_disable,
    });

    registers.cntvoff_el2.write(0);

    registers.hcr_el2.modify(.{ .rw = .el1_is_aarch64 });

    registers.spsr_el2.write(.{
        .m = .el1h,
        .d = .masked,
        .i = .masked,
        .a = .masked,
        .f = .masked,
    });

    // fake a return stack pointer and exception link register to a function
    // this function will begin executing when we do `eret` from here
    registers.elr_el2.write(@intFromPtr(&kernelInit));
    registers.sp_el1.write(phys_boot_core_stack_end_exclusive);

    asm volatile ("mov x29, xzr");
    asm volatile ("mov x30, xzr");

    arch.cpu.eret();

    unreachable;
}

// TODO: re-enable this when
// https://github.com/ziglang/zig/issues/16327 is fixed.

const StackTrace = std.builtin.StackTrace;

pub fn panic(msg: []const u8, stack: ?*StackTrace, return_addr: ?usize) noreturn {
    @setCold(true);

    if (return_addr) |ret| {
        kerror(@src(), "[{x:0>8}] {s}", .{ ret, msg });
    } else {
        kerror(@src(), "[unknown] {s}", .{msg});
    }

    if (stack) |stack_trace| {
        for (stack_trace.instruction_addresses, 0..) |addr, i| {
            kprint("{d}: {x:0>8}\n", .{ i, addr });
        }
    }

    @breakpoint();

    unreachable;
}

// The assembly portion of soft reset (does the stack magic)
pub extern fn _soft_reset(resume_address: u64) noreturn;

pub fn resetSoft() noreturn {
    _soft_reset(@intFromPtr(&kernelInit));
}
