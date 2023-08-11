const std = @import("std");
const ForthError = @import("errors.zig").ForthError;

const Allocator = std.mem.Allocator;

pub fn same(a: []const u8, b: []const u8) bool {
   var l = chIndex(0, a) catch {
       std.debug.print("Null terminator not found! {s}\n", .{a});
       return false;
   };
   return std.mem.eql(u8, a[0..l], b[0..l]);
}
 
pub fn chIndex(ch: u8, s: []const u8) !usize {
   for(0..s.len) |i| {
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
    for(0..len) |i| {
        result[i] = src[i];
    }
    //result[len] = 0;
    return result.ptr;
}

pub fn asSlice(s: [*] u8) [] u8 {
  var l: usize = 0;
  while(s[l] != 0) {
    l += 1;
  }
  return s[0..l];
}

pub fn clear(s: [:0]u8) void {
    @memset(s, 0);
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
