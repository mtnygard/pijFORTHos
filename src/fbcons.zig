const std = @import("std");
const root = @import("root");
const debug = root.debug;
const kinfo = root.kinfo;
const kprint = root.kprint;

const frame_buffer = @import("frame_buffer.zig");
const FrameBuffer = frame_buffer.FrameBuffer;

const hal = @import("hal.zig");
const VideoController = hal.common.VideoController;
const Serial = hal.common.Serial;
const Allocator = std.mem.Allocator;

const Readline = @import("readline.zig");

const character_rom = @embedFile("data/character_rom.bin");

pub const default_palette = [_]u32{
    0x00000000,
    0xFFBB5500,
    0xFFFFFFFF,
    0xFFFF0000,
    0xFF00FF00,
    0xFF0000FF,
    0x55555555,
    0xCCCCCCCC,
};

/// display console
pub const FrameBufferConsole = struct {
    // These are palette indices
    pub const COLOR_FOREGROUND: u8 = 0x02;
    pub const COLOR_BACKGROUND: u8 = 0x00;
    pub const COLOR_HIGHLIGHT: u8 = 0x04;
    pub const COLOR_LT_GREY: u8 = 0x06;

    pub const FONT_WIDTH: u8 = 8;
    pub const FONT_HEIGHT: u8 = 16;

    tab_width: u8 = 8,
    xpos: u64 = 0,
    ypos: u64 = 0,
    width: u64 = undefined,
    height: u64 = undefined,
    fg_color: u8 = undefined,
    bg_color: u8 = undefined,
    full_height: u64 = undefined,
    fb: *FrameBuffer = undefined,
    serial: *Serial = undefined,

    pub fn init(self: *FrameBufferConsole, serial: *Serial) void {
        self.serial = serial;
        self.xpos = 0;
        self.ypos = 0;
        self.width = @truncate(self.fb.xres / FONT_WIDTH);
        self.full_height = @truncate(self.fb.yres / FONT_HEIGHT);
        self.height = self.full_height - 1;
        self.fg_color = COLOR_FOREGROUND;
        self.bg_color = COLOR_BACKGROUND;
    }

    pub fn clear(self: *FrameBufferConsole) void {
        self.fillRegion(0, 0, self.width, self.height, self.bg_color);
        self.xpos = 0;
        self.ypos = 0;
    }

    fn next(self: *FrameBufferConsole) void {
        self.xpos += 1;
        if (self.xpos >= self.width) {
            self.nextLine();
        }
    }

    fn nextTab(self: *FrameBufferConsole) void {
        var positions = self.tab_width - (self.xpos % self.tab_width);
        self.xpos += positions;
        if (self.xpos >= self.width) {
            self.nextLine();
        }
    }

    fn nextLine(self: *FrameBufferConsole) void {
        self.xpos = 0;
        self.ypos += 1;
        if (self.ypos >= self.height) {
            self.nextScreen();
        }
        self.fillRegion(0, self.ypos, self.width, 1, self.bg_color);
    }

    fn nextScreen(self: *FrameBufferConsole) void {
        // self.fb.blit(0, 16, self.fb.xres, self.fb.yres - 16, 0, 0);
        // self.fb.clearRegion(0, self.fb.yres - 16, self.fb.xres, 16);
        // self.ypos = self.height - 1;

        self.xpos = 0;
        self.ypos = 0;
    }

    fn eraseCursor(self: *FrameBufferConsole) void {
        self.underbar(self.bg_color);
    }

    fn drawCursor(self: *FrameBufferConsole) void {
        self.underbar(self.fg_color);
    }

    fn backspace(self: *FrameBufferConsole) void {
        if (self.xpos > 0) {
            self.xpos -= 1;
        }
        self.fillRegion(self.xpos, self.ypos, 1, 1, self.bg_color);
    }

    fn isPrintable(ch: u8) bool {
        return ch >= 32;
    }

    pub fn emit(self: *FrameBufferConsole, ch: u8) void {
        self.eraseCursor();
        defer self.drawCursor();

        switch (ch) {
            0x0c => self.clear(),
            0x7f => self.backspace(),
            '\t' => self.nextTab(),
            '\n' => self.nextLine(),
            else => if (isPrintable(ch)) {
                self.drawChar(self.xpos, self.ypos, self.fg_color, self.bg_color, ch);
                self.next();
            },
        }
    }

    pub fn emitString(self: *FrameBufferConsole, str: []const u8) void {
        self.eraseCursor();
        defer self.drawCursor();

        for (str) |ch| {
            self.emit(ch);
        }
    }

    // Font is fixed height of 16 bits, fixed width of 8 bits. Colors are palette indices.
    pub fn drawChar(self: *FrameBufferConsole, x: usize, y: usize, fg: u8, bg: u8, ch: u8) void {
        var romidx: usize = @as(usize, ch - 32) * 16;
        if (romidx + 16 >= character_rom.len)
            return;

        var base = self.fb.base;
        var line_stride = self.fb.pitch;
        var fbidx = (x * FONT_WIDTH) + (y * FONT_HEIGHT * line_stride);

        for (0..16) |_| {
            var charbits: u8 = character_rom[romidx];
            for (0..8) |_| {
                base[fbidx] = if ((charbits & 0x80) != 0) fg else bg;
                fbidx += 1;
                charbits <<= 1;
            }
            fbidx -= 8;
            fbidx += line_stride;
            romidx += 1;
        }
    }

    fn underbar(self: *FrameBufferConsole, color: u8) void {
        self.fb.fillRegion(self.xpos * FONT_WIDTH, (self.ypos + 1) * FONT_HEIGHT, FONT_WIDTH, 1, color);
    }

    fn fillRegion(self: *FrameBufferConsole, start_col: usize, start_row: usize, cols: usize, rows: usize, color: u8) void {
        self.fb.fillRegion(start_col * FONT_WIDTH, start_row * FONT_HEIGHT, cols * FONT_WIDTH, rows * FONT_HEIGHT, color);
    }

    pub fn fillStatus(self: *FrameBufferConsole, color: u8) void {
        self.fillRegion(0, self.full_height - 1, self.width, 1, color);
    }

    pub fn clearStatus(self: *FrameBufferConsole) void {
        self.fillStatus(COLOR_LT_GREY);
    }

    pub fn emitStatus(self: *FrameBufferConsole, str: []const u8) void {
        const save_xpos = self.xpos;
        const save_ypos = self.ypos;
        const save_fg_color = self.fg_color;
        const save_bg_color = self.bg_color;
        self.eraseCursor();

        defer {
            self.xpos = save_xpos;
            self.ypos = save_ypos;
            self.fg_color = save_fg_color;
            self.bg_color = save_bg_color;
            self.drawCursor();
        }

        self.clearStatus();
        self.xpos = 0;
        self.ypos = self.full_height - 1;
        self.bg_color = COLOR_LT_GREY;
        self.fg_color = COLOR_HIGHLIGHT;
        self.emitString(str);
    }

    pub const Writer = std.io.Writer(*FrameBufferConsole, error{}, write);

    pub fn write(self: *FrameBufferConsole, bytes: []const u8) !usize {
        for (bytes) |ch| {
            self.emit(ch);
        }
        return bytes.len;
    }

    pub fn writer(self: *FrameBufferConsole) Writer {
        return .{ .context = self };
    }

    pub fn print(self: *FrameBufferConsole, comptime fmt: []const u8, args: anytype) !void {
        try self.writer().print(fmt, args);
    }

    pub fn readLine(self: *FrameBufferConsole, prompt: []const u8, buffer: []u8) usize {
        var i: usize = 0;
        var ch: u8 = 0;
        var echo: bool = true;

        self.emitString(prompt);

        while (i < (buffer.len - 1) and !newline(ch)) {
            echo = true;
            ch = self.getc();

            switch (ch) {
                0x7f => if (i > 0) {
                    i -= 1;
                } else {
                    echo = false;
                },
                else => {
                    buffer[i] = ch;
                    i += 1;
                },
            }
            if (echo) {
                self.putc(ch);
            }
            buffer[i] = 0;
        }
        return i;
    }

    pub fn getc(self: *FrameBufferConsole) u8 {
        var ch = self.serial.getc();
        return if (ch == '\r') '\n' else ch;
    }

    pub fn putc(self: *FrameBufferConsole, ch: u8) void {
        self.serial.putc(ch);
        self.emit(ch);
    }

    pub fn char_available(self: *FrameBufferConsole) bool {
        return self.serial.hasc();
    }
};

fn newline(ch: u8) bool {
    return ch == '\r' or ch == '\n';
}

fn readLineThunk(ctx: *anyopaque, prompt: []const u8, buffer: []u8) Readline.Error!usize {
    var console: *FrameBufferConsole = @ptrCast(@alignCast(ctx));
    return console.readLine(prompt, buffer);
}

pub fn createReader(allocator: Allocator, console: *FrameBufferConsole) !*Readline {
    return Readline.init(allocator, console, readLineThunk);
}
