const std = @import("std");
const bsp = @import("bsp.zig");
const Allocator = std.mem.Allocator;
const Readline = @import("readline.zig");

/// display console
pub const FrameBufferConsole = struct {
    tab_width: u8 = 8,
    xpos: u8 = 0,
    ypos: u8 = 0,
    width: u16 = undefined,
    height: u16 = undefined,
    frame_buffer: *bsp.video.FrameBuffer = undefined,

    pub fn init(self: *FrameBufferConsole) void {
        self.xpos = 0;
        self.ypos = 0;
        self.width = @truncate(self.frame_buffer.xres / 8);
        self.height = @truncate(self.frame_buffer.yres / 16);
    }

    pub fn clear(self: *FrameBufferConsole) void {
        self.frame_buffer.clear();
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
    }

    fn nextScreen(self: *FrameBufferConsole) void {
        self.xpos = 0;
        self.ypos = 0;
        // TODO: clear screen?
    }

    fn underbar(self: *FrameBufferConsole, color: u8) void {
        var x: u16 = self.xpos;
        x *= 8;
        var y: u16 = self.ypos + 1;
        y *= 16;

        for (0..8) |i| {
            self.frame_buffer.drawPixel(x + i, y, color);
        }
    }

    fn eraseCursor(self: *FrameBufferConsole) void {
        self.underbar(bsp.video.FrameBuffer.COLOR_BACKGROUND);
    }

    fn drawCursor(self: *FrameBufferConsole) void {
        self.underbar(bsp.video.FrameBuffer.COLOR_FOREGROUND);
    }

    fn backspace(self: *FrameBufferConsole) void {
        if (self.xpos > 0) {
            self.xpos -= 1;
        }
        self.frame_buffer.eraseChar(@as(u16, self.xpos) * 8, @as(u16, self.ypos) * 16);
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
                self.frame_buffer.drawChar(@as(u16, self.xpos) * 8, @as(u16, self.ypos) * 16, ch);
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
        _ = self;
        var ch = bsp.io.receive();
        return if (ch == '\r') '\n' else ch;
    }

    pub fn putc(self: *FrameBufferConsole, ch: u8) void {
        bsp.io.send(ch);
        self.emit(ch);
    }

    pub fn char_available(self: *FrameBufferConsole) bool {
        _ = self;
        return bsp.io.byte_available();
    }
};

fn newline(ch: u8) bool {
    return ch == '\r' or ch == '\n';
}

fn readLineThunk(ctx: *anyopaque, prompt: []const u8, buffer: []u8) usize {
    var console: *FrameBufferConsole = @ptrCast(@alignCast(ctx));
    return console.readLine(prompt, buffer);
}

pub fn createReader(allocator: Allocator, console: *FrameBufferConsole) !*Readline {
    return Readline.init(allocator, console, readLineThunk);
}
