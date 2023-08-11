const std = @import("std");
const string = @import("string.zig");
const ForthTokenIterator = @import("parser.zig").ForthTokenIterator;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const print = std.debug.print;

const Value = struct {
    data: u8,
};

const WordFunction = *const fn (forth: *Forth, header: *Header) ForthError!void;

const Header = struct {
    name: [20:0]u8 = undefined,
    func: WordFunction = undefined,
    value: Value = undefined,
    immediate: bool = false,
    previous: ?*Header = null,

    pub fn init(name: []const u8, func: WordFunction, immediate: bool, previous: ?*Header) Header {
        var this = Header{
            .name = undefined,
            .func = func,
            .immediate = immediate,
            .previous = previous,
        };
        string.copyTo(&this.name, name);
        return this;
    }

    pub fn bodyOfType(this: *Header, comptime T: type) T {
        const p = this.raw_body();
        return @alignCast(@ptrCast(alignedByType(p, T)));
    } 

    pub fn body(this: *Header, comptime T: type) *T {
        const p = this.raw_body();
        return @alignCast(@ptrCast(alignedByType(p, T)));
    } 

    pub fn raw_body(this: *Header) [*]u8 {
        const i: usize = @intFromPtr(this) + @sizeOf(Header);
        return @ptrFromInt(i);
    } 
};

const HeaderP = *Header;

fn alignedByType(p: [*]u8, comptime T: type) [*]u8 {
    return alignedBy(p, @alignOf(T));
}

fn alignedBy(p: [*]u8, alignment: usize) [*]u8 {
     const i: usize = @intFromPtr(p);
     var words = (i + alignment - 1) / alignment;
     return @ptrFromInt(words * alignment);
}

const Memory = struct {
    p: [*]u8,                // The data
    length: usize,           // Length of the data.
    current: [*]u8,          // Next Free memory space.
    alignment: usize = @alignOf(*void),

    pub fn init(p: [*]u8, length: usize) Memory {
        return Memory{
            .p = p,
            .length = length,
            .current = p,
        };
    }

    //pub fn at(_: *Memory, comptime T: type, p: [*]u8) *T {
    //    return @alignCast(@constCast(@ptrCast(p)));
    //}

    pub fn addString(this: *Memory, s: []const u8) [*]u8 {
        const result = this.current;
        var current = this.rawAddBytes(@constCast(@ptrCast(s.ptr)), s.len);
        current[0] = 0;
        current += 1;
        this.current = current;
        return result;
    }

    pub fn addU64(this: *Memory, x: u64) *u64 {
        return this.addScalar(u64, x);
    }

    pub fn addScalar(this: *Memory, comptime T: type, x: anytype ) *T {
        this.current = alignedByType(this.current, T);
        const result = this.current;
        this.current = this.rawAddScalar(T, x);
        return @alignCast(@ptrCast(result));
    }

    fn rawAddScalar(this: *Memory, comptime T: type, x: anytype ) [*]u8 {
        const len = @sizeOf(T);
        const p: [*]u8 = @alignCast(@constCast(@ptrCast(&x)));
        var current = this.rawAddBytes(p, len);
        return current;
    }

    // Copy bytes into the current location of memory but does
    // not move the current index. Returns the resulting (unaligned)
    // current index.
    fn rawAddBytes(this: *Memory, src: [*]u8, n: usize) [*]u8 {
        print("raw add bytes: n: {}\n", .{n});
        var current = this.current;
        for(0..n) |i| {
            current[i] = src[i];
        }
        return current + n;
    }
};

pub const Forth = struct {
    memory: *Memory = undefined,
    lastWord: ?*Header = null,
    newWord: ?*Header = null,

    pub fn init(memory: *Memory) Forth {
        return Forth{.memory = memory};
    }

    pub fn findWord(this: *Forth, name: []const u8) ?*Header {
        var e = this.lastWord;
        while(e) |entry| {
            print("Name: {s}\n", .{entry.name});
            if (string.same(&e.?.name, name)) {
                return e.?;
            }
            e = e.?.previous;
        }
        return null;
    }

    pub fn startWord(this: *Forth, name: []const u8, f: WordFunction, immediate: bool) *Header {
        const entry: Header = Header.init(name, f, immediate, this.lastWord);
        this.newWord = this.memory.addScalar(Header, entry);
        return this.newWord.?;
    }

    pub fn completeWord(this: *Forth) *Header {
        const result = this.newWord;
        this.lastWord = this.newWord;
        this.newWord = null;
        return result.?;
    }

    pub fn dump(this: *Forth) void {
        print("Dump:\n", .{});
        var e = this.lastWord;
        while(e != null) {
            const p = @intFromPtr(e);
            print("e: {x}\n", .{p});
            print("Name: {s}\n", .{e.?.name});
            e = e.?.previous;
        }
        print("----\n\n", .{});
    }

    pub fn addNumber(this: Forth, v: u64) *u64 {
        return this.memory.addU64(v);
    }

    pub fn addString(this: Forth, s: []const u8) [*]u8 {
        return this.memory.addString(s);
    }

    pub fn addScalar(this: Forth, comptime T: type, x: anytype) *T {
        return this.memory.addScalar(T, x);
    }
};

pub fn hello(_: *Forth, header: *Header) ForthError!void {
    print("Hello\n", .{});
    print("Header: {any}\n", .{header});
    const body = header.body(u64);
    print("body: {}\n", .{body.*});
    
}

pub fn dot(_: *Forth, header: *Header) ForthError!void {
    print("Dot\n", .{});
    print("Header: {any}\n", .{header});
    const body = header.bodyOfType([*:0]u8);
    print("Body: {s}\n", .{body});
}

pub fn dotInts(_: *Forth, header: *Header) ForthError!void { 
    print("DotI\n", .{});
    const body = header.bodyOfType(*[4]u64);
    print("Body: {any}\n", .{body.*});
}

pub fn inner(forth: *Forth, header: *Header) ForthError!void { 
    _ = forth;
    print("\n\ninner: header: {any}\n\n", .{header});
    var body = header.bodyOfType([*]u64);
    //var i: usize = 0;
    for(0..3) |i| {
        print("thing: {x}\n", .{body[i]});
    }
    print("\n\ninner: done\n", .{});
}

pub fn main() !void {
    var buf: [20000]u8 = undefined;
    var m = Memory.init(&buf, buf.len);

    var forth = Forth.init(&m);
    print("mem: {any}\n", .{m});

    _ = forth.startWord("qqq", &inner, false);
    _ = forth.addNumber(0);
    _ = forth.completeWord();


    var foo: *Header = forth.startWord("foo", &dot, false);
    _ = forth.addString("AACCCD");
    _ = forth.completeWord();

    forth.dump();

    var bar: *Header = forth.startWord("bar", &dotInts, false);
    _ = forth.addNumber(7717);
    _ = forth.addNumber(42);
    _ = forth.addNumber(9);
    _ = forth.addNumber(99999);
    _ = forth.completeWord();

    print("foo: {x}\n", .{&foo});
    print("foo: {x}\n", .{&foo});
    print("bar: {x}\n", .{&bar});

    print("adding scalers\n", .{});
    var sec = forth.startWord("sec", &inner, false);
    _ = forth.addScalar(Header, foo);
    _ = forth.addScalar(Header, foo);
    _ = forth.addScalar(Header, bar);
    _ = forth.addNumber(256);
    _ = forth.addNumber(32000);
    _ = forth.addNumber(0);
    _ = forth.completeWord();


    //print("w1 {any}\n", .{w1});
    print("mem: {any}\n", .{m});
    print("forth: {any}\n", .{forth});

    print("sec: {any}\n", .{sec});
    print("foo: {any}\n", .{foo});
    print("bar: {any}\n", .{bar});
    print("done\n", .{});

    print("==== finding ===\n", .{});
    var xfoo = forth.findWord("foo");
    var xbar = forth.findWord("bar");
    print("foo: {any}\n", .{xfoo.?});
    print("bar: {any}\n", .{xbar.?});

    print("==== finding ===\n", .{});
    var s = "sec";
    var words = ForthTokenIterator.init(s);

    var word = words.next();
    while (word != null) : (word = words.next()) {
        print("in loop\n", .{});
        if (word) |w| {
            print("WORD: [{s}]\n", .{w});
            var xxx = forth.findWord(w);
            if (xxx) |q| {
                print("Found: {any}\n", .{q});
                try q.func(&forth, q);
            } 
            
        }
    }
}
