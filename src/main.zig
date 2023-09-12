const std = @import("std");
const arch = @import("architecture.zig");
const bsp = @import("bsp.zig");
const qemu = @import("qemu.zig");
const heap = @import("heap.zig");
const frame_buffer = @import("frame_buffer.zig");
const fbcons = @import("fbcons.zig");
const bcd = @import("bcd.zig");
const forty = @import("forty/forth.zig");
const Forth = forty.Forth;
const debug = @import("debug.zig");
const raspi3 = @import("bsp/raspi3.zig");

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

const Self = @This();

pub var board = bsp.common.BoardInfo{};
pub var kernel_heap = heap{};
pub var fb: frame_buffer.FrameBuffer = frame_buffer.FrameBuffer{};
pub var frame_buffer_console: fbcons.FrameBufferConsole = fbcons.FrameBufferConsole{ .fb = &fb };
pub var interpreter: Forth = Forth{};

pub var uart_valid = false;
pub var console_valid = false;

fn kernelInit() void {
    // State: one core, no interrupts, no MMU, no heap Allocator, no display, no serial
    arch.cpu.mmuInit();

    kernel_heap.init();
    os.page_allocator = kernel_heap.allocator();

    devicetree.init();

    // TODO: Choose which BSP to instantiate based on a boot time value
    raspi3.init() catch {
        // We can try to emit an error, but there's no guarantee the
        // UART is even going to work.
        bsp.serial.puts("Early init error. Cannot proceed.");
        return;
    };

    // State: one core, no interrupts, MMU, heap Allocator, no display, no serial
    arch.cpu.exceptions.init(&raspi3.irqHandleThunk);

    // State: one core, interrupts, MMU, heap Allocator, no display, no serial
    uart_valid = true;

    // State: one core, interrupts, MMU, heap Allocator, no display, serial
    bsp.video_controller.allocFrameBuffer(&fb, 1024, 768, 8, &frame_buffer.default_palette);

    frame_buffer_console.init(&bsp.serial);
    console_valid = true;

    board.init(&os.page_allocator);
    bsp.info_controller.inspect(&board);

    // bsp.timer.schedule(200000, printOneDot, &.{});

    // State: one core, interrupts, MMU, heap Allocator, display,
    // serial, logging available

    kprint("Board model {s} (a {s}) with {?}MB\n\n", .{
        board.model.name,
        board.model.processor,
        board.model.memory,
    });
    kprint("    MAC address: {?}\n", .{board.device.mac_address});
    kprint("  Serial number: {?}\n", .{board.device.serial_number});
    kprint("Manufactured by: {?s}\n\n", .{board.device.manufacturer});

    diagnostics() catch |err| {
        kerror(@src(), "Error printing diagnostics: {any}\n", .{err});
        bsp.io.uart_writer.print("Error printing diagnostics: {any}\n", .{err}) catch {};
    };

    bsp.usb.powerOn();

    interpreter.init(os.page_allocator, &frame_buffer_console) catch |err| {
        kerror(@src(), "Forth init: {any}\n", .{err});
    };

    interpreter.defineStruct("fbcons", fbcons.FrameBufferConsole) catch |err| {
        kerror(@src(), "Forth defineStruct: {any}\n", .{err});
    };

    supplyAddress("fbcons", @intFromPtr(&frame_buffer_console));
    supplyAddress("fb", @intFromPtr(fb.base));
    supplyUsize("fbsize", fb.buffer_size);

    arch.cpu.exceptions.markUnwindPoint(&arch.cpu.exceptions.global_unwind_point);
    arch.cpu.exceptions.global_unwind_point.pc = @as(u64, @intFromPtr(&repl));

    // State: one core, interrupts, MMU, heap Allocator, display,
    // serial, logging available, exception recovery available
    repl();

    // Does not return
    qemu.exit(0);

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

    try printClockRate(.uart);
    try printClockRate(.core);
    try printClockRate(.arm);
}

fn printClockRate(clock_type: raspi3.bcm_peripheral_clocks.ClockId) !void {
    var min_rate = raspi3.peripheral_clock_controller.clockRateMin(clock_type);
    var max_rate = raspi3.peripheral_clock_controller.clockRateMax(clock_type);
    var current = raspi3.peripheral_clock_controller.clockRateCurrent(clock_type);

    var clock_mhz = current / 1_000_000;
    kprint("{s:>14} clock: current {} MHz (min: {}, max {})\n", .{ @tagName(clock_type), clock_mhz, min_rate / 1_000_000, max_rate / 1_000_000 });
}

export fn _soft_reset() noreturn {
    kernelInit();

    unreachable;
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

// pub fn panic(msg: []const u8, stack: ?*std.builtin.StackTrace, return_addr: ?usize) noreturn {
//     _ = stack;
//     _ = return_addr;

//     kerror(@src(), msg, .{});
//     while (true) {
//         arch.cpu.wfe();
//     }

//     unreachable;
// }
