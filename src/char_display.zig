const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const debug = root.debug;
const kprint = root.kprint;
const Serial = root.HAL.Serial;

const serial = @import("serial.zig");

const FrameBuffer = @import("frame_buffer.zig");
const clamp = FrameBuffer.clamp;

const Readline = @import("readline.zig");
const RichChar = @import("rich_char.zig").RichChar;

const Rectangle = @import("rectangle.zig").Rectangle;
const Point = @import("point.zig").Point;

pub const DEFAULT_FOREGROUND: u8 = 0x01;
pub const DEFAULT_BACKGROUND: u8 = 0x00;

const Self = @This();

/// Character mode display.
/// The naming convention is that x and y are pixel coordinates
/// while rows and columns are character coordinates.
num_cols: u64 = undefined,
num_rows: u64 = undefined,
length: u64 = undefined,

/// The frame buffer, which is what is actually displayed.
fb: *FrameBuffer = undefined,

/// The text that should be on the screen. The idea is that
/// we update .text and then sync it with the screen.
text: [*]RichChar,

/// The location (in pixels) of each character on the screen,
/// saves us from having to compute the location each time
/// we render a character.
location: [*]Point,

/// The top row is the row of text that gets displayed at the top
/// of the framebuffer.
top_row: u64 = 0,

/// The section of .text (in col/row units) that is out of sync
/// with what is currently displayed.
modified_area: Rectangle = undefined,

/// Current colors.
current_fg: u8,
current_bg: u8,

/// Where we want the cursor to display.
current_col: u64 = 0,
current_row: u64 = 0,

/// The position of the cursor as currently drawn on the fb.
displayed_cursor_col: u64 = 0,
displayed_cursor_row: u64 = 0,

pub fn init(allocator: Allocator, fb: *FrameBuffer) !*Self {
    var self: *Self = try allocator.create(Self);

    const num_cols = fb.xres / fb.font_width_px;
    const num_rows = fb.yres / fb.font_height_px;
    const length = num_cols * num_rows;
    const text = try allocator.alloc(RichChar, length);
    const location = try allocator.alloc(Point, length);

    self.* = .{
        .fb = fb,
        .num_cols = num_cols,
        .num_rows = num_rows,
        .length = length,
        .text = text.ptr,
        .location = location.ptr,
        .top_row = 0,
        .modified_area = Rectangle.invalid(),
        .current_fg = DEFAULT_FOREGROUND,
        .current_bg = DEFAULT_BACKGROUND,
        .current_col = 0,
        .current_row = 0,
        .displayed_cursor_col = 0,
        .displayed_cursor_row = 0,
    };

    for (0..num_rows) |row| {
        for (0..num_cols) |col| {
            const i = self.charIndexGet(col, row);
            self.text[i].ch = ' ';
            self.text[i].fg = DEFAULT_FOREGROUND;
            self.text[i].bg = DEFAULT_BACKGROUND;
            self.location[i].x = fb.colToX(col);
            self.location[i].y = fb.rowToY(row);
        }
    }

    return self;
}

/// Sync the screen up with our internal memory version if needed.
pub fn sync(self: *Self) void {
    self.syncText();
    self.syncCursor();
}

/// Sync the text on the screen up with our internal memory version if needed.
pub fn syncText(self: *Self) void {
    if (self.modified_area.valid) {
        try serial.writer.print("Syncing screen, rect is {any}\n", .{self.modified_area});
        self.renderRect(self.modified_area);
        self.modified_area.valid = false;
    }
}

/// Sync the cursor on the screen with what is in memory if needed.
pub fn syncCursor(self: *Self) void {
    if ((self.current_row != self.displayed_cursor_row) or (self.current_col != self.displayed_cursor_col)) {
        self.eraseCursor(self.displayed_cursor_col, self.displayed_cursor_row);
        self.drawCursor(self.current_col, self.current_row);
        self.displayed_cursor_row = self.current_row;
        self.displayed_cursor_col = self.current_col;
    }
}

pub fn drawCursor(self: *Self, col: usize, row: usize) void {
    const i = self.charIndexGet(col, row);
    const ch = self.text[i];
    const pt = self.location[i];
    self.renderCursor(pt.x, pt.y, ch.fg);
}

pub fn eraseCursor(self: *Self, col: usize, row: usize) void {
    const i = self.charIndexGet(col, row);
    const ch = self.text[i];
    const pt = self.location[i];
    self.renderCursor(pt.x, pt.y, ch.bg);
}

/// Unconditionally render the cursor onto the screen.
/// Does not update the internal state.
fn renderCursor(self: *Self, x: u64, y: u64, color: u8) void {
    for (0..self.fb.font_width_px) |i| {
        self.fb.drawPixel(x + i, y + self.fb.font_height_px, color);
    }
}

/// Unconditionally render the given rectangle of text onto the screen.
/// Does not update the internal state.
fn renderRect(self: *Self, rect: Rectangle) void {
    if (!rect.valid) {
        return;
    }

    for (rect.top..rect.bottom) |row| {
        try serial.writer.print("rendering row {}, left: {} right {}\n", .{ row, rect.left, rect.right });
        for (rect.left..rect.right) |col| {
            const i_char = self.charIndexGet(col, row);
            const ch = self.text[i_char];
            const pt = self.location[i_char];
            self.fb.drawChar(pt.x, pt.y, ch.ch, ch.fg, ch.bg);
        }
    }
}

/// Invalidate the whole screen, which will eventually trigger a complete repaint.
pub fn invalidate(self: *Self) void {
    self.modified_area.expand(0, 0);
    self.modified_area.expand(self.num_cols - 1, self.num_rows - 1);
}

// Move the cursor.
pub inline fn cursorMoveTo(self: *Self, col: u64, row: u64) void {
    self.current_col = col;
    self.current_row = row;
}

/// Set the current (in memory) cursor position.
pub fn leftCursor(self: *Self) void {
    if (self.current_col > 0) {
        self.current_col -= 1;
    }
}

pub fn rightCursor(self: *Self) void {
    if (self.current_col < self.num_cols - 1) {
        self.current_col += 1;
    }
}

pub fn upCursor(self: *Self) void {
    if (self.current_row > 0) {
        self.current_row -= 1;
    }
}

pub fn downCursor(self: *Self) void {
    if (self.current_row < self.num_rows - 1) {
        self.current_row += 1;
    }
}

pub fn bolCursor(self: *Self) void {
    // Find the first non-whitespace char in the current line.
    var first_non_whitespace: usize = 0;
    for (0..self.num_cols) |i| {
        if (!self.charGet(i, self.current_row).isWhitespace()) {
            first_non_whitespace = i;
            break;
        }
    }

    self.current_col = first_non_whitespace;
}

pub fn eolCursor(self: *Self) void {
    // Find the last non-whitespace, non-irnorable char in the line.
    var i = self.num_cols - 1;
    while (i > 0) {
        if (!self.charGet(i, self.current_row).isWhitespace()) {
            self.current_col = i;
            break;
        }
        i -= 1;
    }
}

// Clear the screen, move the cursor to 0, 0.
pub fn clearScreen(self: *Self) void {
    for (0..self.length) |i| {
        self.text[i].ch = ' ';
        self.text[i].fg = self.current_fg;
        self.text[i].bg = self.current_bg;
    }
    self.cursorMoveTo(0, 0);
    self.modified_area.expand(0, 0);
    self.modified_area.expand(self.num_cols - 1, self.num_rows - 1);
}

/// Shift the text on a row one character to the right, filling in the
/// last column with a blank. Note that the char at (col, row) is overwritter
/// by it's rightmost neighbor.
pub fn textShiftLeft(self: *Self, col: usize, row: usize) void {
    var start_i = self.charIndexGet(col, row);
    var end_i = self.charIndexGet(self.num_cols - 1, row);
    try serial.writer.print("start_i {} end {}\n", .{ start_i, end_i });

    for (start_i..end_i) |i| {
        self.text[i] = self.text[i + 1];
    }
    self.text[end_i].ch = ' ';
    self.modified_area.expand(col, row);
    self.modified_area.expand(self.num_cols - 1, row);
}

/// Shift the text on a row one character to the right.
pub fn textShiftRight(self: *Self, col: usize, row: usize) void {
    var start_i = self.charIndexGet(self.num_cols - 1, row);
    var end_i = self.charIndexGet(col, row);
    try serial.writer.print("start_i {} end {}\n", .{ start_i, end_i });

    var i: usize = start_i;
    while (i > end_i) {
        self.text[i] = self.text[i - 1];
        i -= 1;
    }
    self.modified_area.expand(col, row);
    self.modified_area.expand(self.num_cols - 1, row);
}

pub fn rowTextSet(self: *Self, row: usize, ch: u8) void {
    var i = self.charIndexGet(0, row);

    for (0..self.num_cols) |_| {
        self.text[i].ch = ch;
        self.text[i].fg = self.current_fg;
        self.text[i].bg = self.current_bg;
        i += 1;
    }
    self.modified_area.expand(0, row);
    self.modified_area.expand(self.num_cols - 1, row);
}

/// Get the text from the given line. Assumes that result is big enough to hold
/// a lines worth of characters.
pub fn rowTextGet(self: *Self, row: usize, result: [*]u8) void {
    @memset(result[0..self.num_cols], ' ');
    self.textGet(self.charIndexGet(0, row), self.num_cols, result);
}

/// Compute the char index for a given col, row.
pub inline fn charIndexGet(self: *Self, col: u64, row: u64) u64 {
    return row * self.num_cols + col;
}

/// Get some text from an arbitrary area of the screen, based on a char index.
pub fn textGet(self: *Self, i_start: usize, len: usize, result: [*]u8) void {
    try serial.writer.print("getText: istart {} len {} result {*}\n", .{ i_start, len, result });
    var i_dst: usize = 0;
    for (i_start..(i_start + len)) |i| {
        result[i_dst] = self.text[i].ch;
        i_dst += 1;
    }
}

pub inline fn charGet(self: *Self, col: u64, row: u64) RichChar {
    const i = self.charIndexGet(col, row);
    return self.text[i];
}

pub inline fn currentCharSet(self: *Self, ch: u8) void {
    const i = self.charIndexGet(self.current_col, self.current_row);
    self.text[i].ch = ch;
    self.text[i].fg = self.current_fg;
    self.text[i].bg = self.current_bg;
    self.modified_area.expand(self.current_col, self.current_row);
}

/// Scroll up by one row, ensuring that the internal state is consistent.
pub fn scrollUp(self: *Self) void {
    // Since scrolling is order sensitive, the first thing we do is sync the
    // screen so that there are no outstanding changes. This will also
    // invalidate self.modified_area, which is fine since we are going
    // to come out of this function with the screen sync'ed up with
    // the in memory state.
    self.sync();

    // Shift the in-memory text up by 1 row.
    const len = self.length - self.num_cols;
    for (0..len) |i_dest| {
        const i_src = i_dest + self.num_cols;
        self.text[i_dest] = self.text[i_src];
    }

    // Shift the image on the screen up by 1 row.
    const src_x = 0;
    const src_y = self.fb.font_height_px;
    const src_w = self.fb.xres;
    const src_h = self.fb.yres - self.fb.font_height_px;
    self.fb.blit(src_x, src_y, src_w, src_h, 0, 0);

    // Clear the in memory version of the bottom row of text.
    var i_char = self.charIndexGet(0, self.num_rows - 1);

    for (0..self.num_cols) |_| {
        self.text[i_char].ch = ' ';
        self.text[i_char].fg = self.current_fg;
        self.text[i_char].bg = self.current_bg;
        i_char += 1;
    }

    // Clear the bottom row on the screen.
    const left: u64 = 0;
    const top: u64 = self.fb.yres - self.fb.font_height_px;
    const right: u64 = self.fb.xres;
    const bottom: u64 = self.fb.yres;
    self.fb.fill(left, top, right, bottom, self.current_bg) catch |err| {
        serial.writer.print("Fill failed on scroll: {}\n", .{err}) catch {};
    };
}

/// Debugging: Dump the in-memory text to the serial port.
pub fn textDump(self: *Self) void {
    _ = serial.puts("===Text ===\r\n");
    for (0..self.num_rows) |row| {
        serial.putc('|');
        for (0..self.num_cols) |col| {
            const ch = self.charGet(col, row);
            serial.putc(ch.ch);
        }
        _ = serial.puts("$\r\n");
    }
    _ = serial.puts("------\r\n");
}

/// Debugging: Dump info about adresses and indices to the serial port.
pub fn infoDump(self: *Self) void {
    const w = serial.writer;
    try w.print("CharDisplay: num_rows: {} num_cols: {} length {}\n", .{ self.num_rows, self.num_cols, self.length });

    for (0..self.num_rows) |row| {
        const i_start = self.charIndexGet(0, row);
        var count: usize = 0;
        for (0..self.num_cols) |col| {
            const ch = self.charGet(col, row);
            if (ch.ch != ' ') {
                count += 1;
            }
        }
        try w.print("Row {} starts at index {}, address {*} and contains {} non-blanks\n", .{ row, i_start, self.text + i_start, count });
    }
}
