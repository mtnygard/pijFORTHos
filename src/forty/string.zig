const std = @import("std");
const DataStack = @import("forth.zig").DataStack;
const ForthError = @import("errors.zig").ForthError;

const stack = @import("stack.zig");
const string = @import("string.zig");

const Allocator = std.mem.Allocator;

pub const MaxLineLen = 256;
pub const LineBuffer = [MaxLineLen:0]u8;

pub fn newline(ch: u8) bool {
    return ch == '\r' or ch == '\n';
}

// Return true if the two (possibly zero terminated) slices are equal.
pub fn same(a: []const u8, b: []const u8) bool {
    const alen = chIndex(0, a) catch a.len;
    const blen = chIndex(0, b) catch b.len;

    //std.debug.print("same: {s} {s} {} {}\n", .{a, b, alen, blen});

    if (alen != blen) {
        return false;
    }

    return std.mem.eql(u8, a[0..alen], b[0..blen]);
}

// Return true if the two zero terminated strings are equal.
pub fn streql(a: [*:0]const u8, b: [*:0]const u8) bool {
    const alen = strlen(a);
    const blen = strlen(b);

    if (alen != blen) {
        return false;
    }

    for (0..alen) |i| {
        if (a[i] != b[i]) {
            return false;
        }
    }
    return true;
}

pub fn strlen(s: [*:0]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) {
        i += 1;
    }
    return i;
}

pub fn chIndex(ch: u8, s: []const u8) !usize {
    for (0..s.len) |i| {
        if (s[i] == ch) {
            return i;
        }
    }
    return ForthError.BadOperation;
}

pub fn copyTo(dst: [:0]u8, src: []const u8) void {
    clear(dst);
    const l = @min(dst.len - 1, src.len);
    var i: usize = 0;
    while (i < l) {
        if (src[i] == 0) {
            break;
        }
        dst[i] = src[i];
        i += 1;
    }
    dst[i] = 0;
}

pub fn dupCString(allocator: Allocator, src: [*:0]const u8) ![*]u8 {
    const len = std.mem.indexOfSentinel(u8, 0, src);
    const result = try allocator.alloc(u8, len);
    for (0..len) |i| {
        result[i] = src[i];
    }
    //result[len] = 0;
    return result.ptr;
}

pub fn asSlice(s: [*]u8) []u8 {
    var l: usize = 0;
    while (s[l] != 0) {
        l += 1;
    }
    return s[0..l];
}

pub fn clear(s: [:0]u8) void {
    @memset(s, 0);
}

pub fn toPrintable(ch: u8) u8 {
    return if ((ch >= ' ') and (ch <= '~')) ch else '.';
}

pub fn u64ToChars(i: u64) [8]u8 {
    var result: [8]u8 = undefined;

    var j = i;
    for (0..8) |iChar| {
        const ch: u8 = @truncate(j);
        result[iChar] = toPrintable(ch);
        j = j >> 8;
    }
    return result;
}

const digitChars = "0123456789abcdefghijklmnopqrstuvwxyz";

pub fn formatInteger(comptime T: type, value: T, base: u64, buf: [*]u8) usize {
    var v: T = value;
    var b: T = @intCast(base);

    var offset: usize = 0;

    if (value < 0) {
        v = -1 * v;
    }

    if (v == 0) {
        buf[offset] = '0';
        offset += 1;
    } else {
        while (v != 0) {
            //const uValue: u64 = @intCast(v);
            buf[offset] = digitChars[@intCast(@rem(v, b))];
            offset += 1;
            v = @divTrunc(v, b);
        }

        if (value < 0) {
            buf[offset] = '-';
            offset += 1;
        }
        std.mem.reverse(u8, buf[0..offset]);
    }
    return offset;
}

// There has got to be a better way!
pub fn simpleFormat(buf: [*:0]u8, fmt: [*:0]const u8, data: *DataStack) !void {
    var iBuf: usize = 0;
    var iFmt: usize = 0;
    var len = string.strlen(fmt);

    while (iFmt < len) {
        const ch = fmt[iFmt];
        switch (ch) {
            0 => break,
            '%' => {
                var value = try data.pop();
                iFmt += 1;
                const fmtCh = fmt[iFmt];
                switch (fmtCh) {
                    'c' => {
                        buf[iBuf] = @truncate(value);
                        iBuf += 1;
                    },
                    'C' => {
                        for (0..8) |_| {
                            buf[iBuf] = @truncate(value);
                            value = value >> 8;
                            iBuf += 1;
                        }
                    },
                    'd' => {
                        const iValue: i64 = @bitCast(value);
                        iBuf += formatInteger(i64, iValue, 10, buf + iBuf);
                    },
                    'x' => {
                        buf[iBuf] = '0';
                        buf[iBuf + 1] = 'x';
                        iBuf += 2;
                        const iValue: i64 = @bitCast(value);
                        iBuf += formatInteger(i64, iValue, 16, buf + iBuf);
                    },
                    's' => {
                        const s: [*:0]u8 = @ptrFromInt(value);
                        const l = string.strlen(s);
                        for (0..l) |i| {
                            buf[iBuf] = s[i];
                            iBuf += 1;
                        }
                    },

                    else => return ForthError.FormatError,
                }
            },
            '\\' => {
                iFmt += 1;
                buf[iBuf] = fmt[iFmt];
            },
            else => {
                buf[iBuf] = ch;
                iBuf += 1;
            },
        }
        iFmt += 1;
    }
    buf[iBuf] = 0;
}

test "duplicating a slice" {
    //const print = std.debug.print;
    const assert = std.debug.assert;
    const allocator = std.testing.allocator;

    const s = "abcdef";
    const p = try dupCString(allocator, s);
    assert(p[0] == 'a');

    allocator.free(p);
}
