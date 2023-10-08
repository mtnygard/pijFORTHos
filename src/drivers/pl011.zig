const root = @import("root");
const std = @import("std");
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const RingBuffer = std.RingBuffer;

const hal = @import("../hal.zig");
const InterruptController = hal.common.InterruptController;
const IrqId = hal.common.IrqId;

const bcm_gpio = @import("bcm_gpio.zig");
const BroadcomGpio = bcm_gpio.BroadcomGpio;

const arch = @import("../architecture.zig");
const cpu = arch.cpu;

extern fn spinDelay(cpu_cycles: u32) void;

pub const Pl011Uart = struct {
    const DataRegister = packed struct {
        data: u8,
        framing_error: u1 = 0,
        parity_error: u1 = 0,
        break_error: u1 = 0,
        overrun_error: u1 = 0,
        _unused_reserved: u20 = 0,
    };

    const ReceiveStatusErrorClearRegister = packed struct {
        framing_error: u1 = 0,
        parity_error: u1 = 0,
        break_error: u1 = 0,
        overrun_error: u1 = 0,
        _unused_reserved: u28 = 0,
    };

    const FlagsRegister = packed struct {
        clear_to_send: u1 = 0,
        _unused_dsr: u1 = 0,
        _unused_dcd: u1 = 0,
        busy: u1 = 0,
        receive_fifo_empty: u1 = 0,
        transmit_fifo_full: u1 = 0,
        receive_fifo_full: u1 = 0,
        transmit_fifo_empty: u1 = 0,
        _unused_ri: u1 = 0,
        _unused_reserved: u23 = 0,
    };

    const IntegerBaudRateRegister = packed struct {
        integer_baud_rate_divisor: u16,
        _unused_reserved: u16 = 0,
    };

    const FractionalBaudRateRegister = packed struct {
        fractional_baud_rate_divisor: u6,
        _unused_reserved: u26 = 0,
    };

    const EnableBitP = enum(u1) {
        disable = 0,
        enable = 1,
    };

    const LineControlRegister = packed struct {
        send_break: u1 = 0,
        parity_enable: u1 = 0,
        even_parity_select: u1 = 0,
        two_stop_bit_select: u1 = 0,
        fifo_enable: EnableBitP = .disable,
        word_length: enum(u2) {
            eight_bits = 0b11,
            seven_bits = 0b10,
            six_bits = 0b01,
            five_bits = 0b00,
        } = .eight_bits,
        stick_parity_select: u1 = 0,
        _unused_reserved: u24 = 0,
    };

    const ControlRegister = packed struct {
        uart_enable: EnableBitP = .disable, // [0]
        _unused_siren: u1 = 0, // [1]
        _unused_sirlp: u1 = 0, // [2]
        _unused_reserved: u4 = 0, // [6:3]
        loopback_enable: EnableBitP = .disable, // [7]
        transmit_enable: EnableBitP = .disable, // [8]
        receive_enable: EnableBitP = .disable, // [9]
        _unused_dtr: u1 = 0, // [10]
        request_to_send: u1 = 0, // [11]
        _unused_out1: u1 = 0, // [12]
        _unused_out2: u1 = 0, // [13]
        request_to_send_flow_control_enable: EnableBitP = .disable, // [14]
        clear_to_send_flow_control_enable: EnableBitP = .disable, // [15]
        _unused_reserved_2: u16 = 0, // [16:31]
    };

    const FifoLevelSelect = enum(u3) {
        one_eighth = 0b000,
        one_quarter = 0b001,
        one_half = 0b010,
        three_quarters = 0b011,
        seven_eighths = 0b100,
    };

    const InterruptFifoLevelSelectRegister = packed struct {
        transmit_interrupt_fifo_level_select: FifoLevelSelect = .one_eighth,
        receive_interrupt_fifo_level_select: FifoLevelSelect = .one_eighth,
        _unused_reserved: u26 = 0,
    };

    const InterruptBit = enum(u1) {
        not_raised = 0,
        raised = 1,
    };

    const InterruptMaskSetClearRegister = packed struct {
        _unused_rimm: u1 = 0,
        clear_to_send_modem_interrupt_mask: InterruptBit = .not_raised,
        _unused_dcdmim: u1 = 0,
        _unused_dsrmim: u1 = 0,
        receive_interrupt_mask: InterruptBit = .not_raised,
        transmit_interrupt_mask: InterruptBit = .not_raised,
        receive_timeout_interrupt_mask: InterruptBit = .not_raised,
        framing_error_interrupt_mask: InterruptBit = .not_raised,
        parity_error_interrupt_mask: InterruptBit = .not_raised,
        break_error_interrupt_mask: InterruptBit = .not_raised,
        overrun_error_interrupt_mask: InterruptBit = .not_raised,
        _unused_reserved: u21 = 0,
    };

    const RawInterruptStatusRegister = packed struct {
        _unused_rirmis: u1 = 0,
        clear_to_send_modem_interrupt_status: InterruptBit = .not_raised,
        _unused_dcdrmis: u1 = 0,
        _unused_dsrrmis: u1 = 0,
        receive_interrupt_status: InterruptBit = .not_raised,
        transmit_interrupt_status: InterruptBit = .not_raised,
        receive_timeout_interrupt_status: InterruptBit = .not_raised,
        framing_error_interrupt_status: InterruptBit = .not_raised,
        parity_error_interrupt_status: InterruptBit = .not_raised,
        break_error_interrupt_status: InterruptBit = .not_raised,
        overrun_error_interrupt_status: InterruptBit = .not_raised,
        _unused_reserved: u21 = 0,
    };

    const MaskedInterruptStatusRegister = packed struct {
        _unused_rimmis: u1 = 0, // [0]
        clear_to_send_masked_interrupt_status: InterruptBit = .not_raised, // [1]
        _unused_dcdmmis: u1 = 0, // [2]
        _unused_dsrmmis: u1 = 0, // [3]
        receive_masked_interrupt_status: InterruptBit = .not_raised, // [4]
        transmit_masked_interrupt_status: InterruptBit = .not_raised, // [5]
        receive_timeout_masked_interrupt_status: InterruptBit = .not_raised, // [6]
        framing_error_masked_interrupt_status: InterruptBit = .not_raised, // [7]
        parity_error_masked_interrupt_status: InterruptBit = .not_raised, // [8]
        break_error_masked_interrupt_status: InterruptBit = .not_raised, // [9]
        overrun_error_masked_interrupt_status: InterruptBit = .not_raised, // [10]
        _unused_reserved: u21 = 0,
    };

    const InterruptClearRegister = packed struct {
        _unused_rimic: u1 = 0,
        clear_to_send_interrupt_clear: InterruptBit = .not_raised,
        _unused_dcdmic: u1 = 0,
        _unused_dsrmic: u1 = 0,
        receive_interrupt_clear: InterruptBit = .not_raised,
        transmit_interrupt_clear: InterruptBit = .not_raised,
        receive_timeout_interrupt_clear: InterruptBit = .not_raised,
        framing_error_interrupt_clear: InterruptBit = .not_raised,
        parity_error_interrupt_clear: InterruptBit = .not_raised,
        break_error_interrupt_clear: InterruptBit = .not_raised,
        overrun_error_interrupt_clear: InterruptBit = .not_raised,
        _unused_reserved: u21 = 0,
    };

    const Registers = extern struct {
        data: DataRegister, // 0x00
        rsrecr: ReceiveStatusErrorClearRegister, // 0x04
        _reserved_0: [4]u32, // 0x08 - 0x14
        flags: FlagsRegister, // 0x18
        _reserved_1: u32 = 0, //0x1c
        _unused_0: u32 = 0, //0x20
        ibaud_rate_divisor: IntegerBaudRateRegister, // 0x24
        fbaud_rate_divisor: FractionalBaudRateRegister, // 0x28
        line_control: LineControlRegister, // 0x2c
        control: ControlRegister, // 0x30
        interrupt_fifo_level_select: InterruptFifoLevelSelectRegister, //0x34
        interrupt_mask_set_clear: InterruptMaskSetClearRegister, // 0x38
        raw_interrupt_status: RawInterruptStatusRegister, // 0x3c
        masked_interrupt_status: MaskedInterruptStatusRegister, //0x40
        interrupt_clear: InterruptClearRegister, //0x44
    };

    irq: IrqId,

    registers: *volatile Registers = undefined,
    intc: *hal.common.InterruptController = undefined,
    fba: FixedBufferAllocator = undefined,
    buffer_space: [128]u8 = undefined,
    read_buffer: RingBuffer = undefined,
    write_buffer: RingBuffer = undefined,

    pub fn init(self: *Pl011Uart, base: u64, interrupt_controller: *hal.common.InterruptController, gpio: *BroadcomGpio) void {
        self.registers = @ptrFromInt(base);
        self.intc = interrupt_controller;
        self.fba = FixedBufferAllocator.init(&self.buffer_space);
        self.read_buffer = RingBuffer.init(self.fba.allocator(), 64) catch unreachable;
        self.write_buffer = RingBuffer.init(self.fba.allocator(), 64) catch unreachable;

        // Configure GPIO pins for serial I/O
        gpio.pins[14].enable();
        gpio.pins[15].enable();

        gpio.pins[14].selectFunction(.alt0);
        gpio.pins[15].selectFunction(.alt0);

        // Turn UART off while initializing
        self.registers.control.uart_enable = .disable;

        // Flush the transmit FIFO
        self.registers.line_control.fifo_enable = .disable;

        // Clear all pending interrupts
        const clear_all: u32 = 0x00;
        self.registers.interrupt_clear = @bitCast(clear_all);

        // From the PL011 Technical Reference Manual:
        //
        // The LCR_H, IBRD, and FBRD registers form the single 30-bit wide LCR Register that is
        // updated on a single write strobe generated by a LCR_H write. So, to internally update the
        // contents of IBRD or FBRD, a LCR_H write must always be performed at the end.
        //
        // Set the baud rate, 8N1 and FIFO disabled.
        //
        // Formula is 48,000,000 hz / (16 * 115200 baud) = 26.0417
        // IBRD = 26 = 0x1a
        // FBRD = ((0.417 * 64) + 0.5) = 27 = 0x1b
        self.registers.ibaud_rate_divisor.integer_baud_rate_divisor = 0x1a;
        self.registers.fbaud_rate_divisor.fractional_baud_rate_divisor = 0x1b;
        self.registers.line_control = .{
            .word_length = .eight_bits,
            .fifo_enable = .disable,
        };

        // Enable receive interrupts. Transmit interrupts are enabled
        // later when data is written.
        self.registers.interrupt_mask_set_clear.receive_interrupt_mask = .raised;
        self.registers.control = .{ .transmit_enable = .enable, .receive_enable = .enable };

        // Turn the UART on
        self.registers.control.uart_enable = .enable;

        // Connect interrupts
        self.intc.connect(self.irq, irqHandleThunk, self);
        self.intc.enable(self.irq);
    }

    pub fn serial(self: *Pl011Uart) hal.common.Serial {
        return hal.common.Serial.init(self);
    }

    pub fn getc(self: *Pl011Uart) u8 {
        while (self.read_buffer.isEmpty()) {
            // block
            cpu.wfi();
        }

        return self.read_buffer.read() orelse 0;
    }

    pub fn putc(self: *Pl011Uart, ch: u8) bool {
        return self.send(ch);
    }

    pub fn puts(self: *Pl011Uart, buf: []const u8) usize {
        //return self.stringSend(buf);
        for (0..buf.len) |i| {
            _ = self.putc(buf[i]);
            // This slows down output enough so that it doesn't panic.
            //            for (0..100) |_| {}
        }
        return buf.len;
    }

    pub fn hasc(self: *Pl011Uart) bool {
        return !self.read_buffer.isEmpty();
    }

    inline fn xmitSpaceAvailable(self: *Pl011Uart) bool {
        return (self.registers.flags.transmit_fifo_full == 0);
    }

    inline fn xmit(self: *Pl011Uart, ch: u8) void {
        self.registers.data.data = ch;
    }

    inline fn recvByteAvailable(self: *Pl011Uart) bool {
        return (self.registers.flags.receive_fifo_empty == 0);
    }

    inline fn recv(self: *Pl011Uart) u8 {
        return self.registers.data.data;
    }

    pub fn irqHandle(self: *Pl011Uart, _: IrqId) void {
        cpu.barriers.barrierMemoryRead();
        defer cpu.barriers.barrierMemoryWrite();

        //  If I uncomment this loop, then characters flow as expected
        //        for (0..100) |_| {}

        //  Or if I uncomment any of the mring.append calls,
        //  characters flow as expected.
        //        root.mring.append("Pl011.irqHandle");

        var interrupts_raised = self.registers.masked_interrupt_status;

        if (interrupts_raised.receive_masked_interrupt_status == .raised) {
            var ch = self.recv();
            self.read_buffer.write(ch) catch {
                // TODO dropped incoming character due to full read buffer.
            };
        }

        if (interrupts_raised.transmit_masked_interrupt_status == .raised) {
            if (self.write_buffer.read()) |ch| {
                // root.mring.append("X");
                self.xmit(ch);
            }

            if (self.write_buffer.isEmpty()) {
                // root.mring.append("E");
                self.registers.interrupt_mask_set_clear.transmit_interrupt_mask = .not_raised;
            }
        }
    }

    // ----------------------------------------------------------------------
    // Buffered IO - interrupt-driven with ring buffer
    // ----------------------------------------------------------------------

    inline fn allowTxInterrupt(self: *Pl011Uart) void {
        self.registers.interrupt_mask_set_clear.transmit_interrupt_mask = .raised;
    }

    inline fn disallowTxInterrupt(self: *Pl011Uart) void {
        self.registers.interrupt_mask_set_clear.transmit_interrupt_mask = .not_raised;
    }

    inline fn xmitInterruptRaised(self: *Pl011Uart) bool {
        return (self.registers.raw_interrupt_status.transmit_interrupt_status == .raised);
    }

    inline fn writeBufferSpaceAvailable(self: *Pl011Uart) usize {
        return self.write_buffer.data.len - self.write_buffer.len();
    }

    pub fn send(self: *Pl011Uart, ch: u8) bool {
        // Add the character to the buffer.
        self.write_buffer.writeAssumeCapacity(ch);

        self.kickstartMyUart();

        return true;
    }

    // If no character is sending, make sure UARTTXINTR will be
    // raised and push the first character into the data register
    fn kickstartMyUart(self: *Pl011Uart) void {
        // If there's room to send a character
        if (self.xmitSpaceAvailable()) {
            // And there's a character to send
            if (self.write_buffer.read()) |ch| {

                // THIS IS THE ANOMALY. Uncommenting this line does
                // NOT result in characters flowing as expected. Only
                // the first character appears, then nothing else.
                for (0..100) |_| {}

                // Make sure we'll receive an interrupt when the
                // character is done sending.
                self.allowTxInterrupt();

                // If I uncomment this line then characters flow as
                // expected.
                // for (0..50) |_| {}

                // But if I use this line, then characters flow, but
                // there is a lot of dropping. The threshold seems to
                // be between 25 and 50 cycles.
                // for (0..25) |_| {}

                // If I uncomment this line, I get a continuous flow
                // of characters but a lot of dropping. This is
                // probably a timing effect rather than an actual
                // coherence problem.
                // cpu.barriers.barrierMemory();

                self.xmit(ch);
            }
        }
    }

    pub fn receive(self: *Pl011Uart) u8 {
        _ = self;
    }
};

pub fn irqHandleThunk(id: IrqId, context: ?*anyopaque) void {
    var uart: *Pl011Uart = @ptrCast(@alignCast(context));
    uart.irqHandle(id);
}
