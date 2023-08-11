const std = @import("std");
const Allocator = std.mem.Allocator;

const bsp = @import("../bsp.zig");
const fbcons = @import("../fbcons.zig");
const stack = @import("stack.zig");
const dict = @import("dictionary.zig");
const value = @import("value.zig");
const core = @import("core.zig");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

pub const init_f = @embedFile("init.f");

const Value = value.Value;
const ValueType = value.ValueType;

const DataStack = stack.Stack(Value);
const ReturnStack = stack.Stack(i32);

const ValueDictionary = dict.Dictionary(Value);

pub const WordFunction = *const fn (self: *Forth) ForthError!void;

const ForthTokenIterator = @import("parser.zig").ForthTokenIterator;

pub const Forth = struct {
    const max_line_len = 256;

    allocator: Allocator = undefined,
    console: *fbcons.FrameBufferConsole = undefined,

    stack: DataStack = undefined,
    rstack: ReturnStack = undefined,
    dictionary: ValueDictionary = undefined,
    memory: [2000]Value = undefined,
    nextFree: i32 = 0,
    nexti: i32 = -999,
    composing: bool = false,
    line_buffer: [max_line_len:0]u8 = undefined,
    words: ForthTokenIterator = undefined,
    new_word_name: [max_line_len:0]u8 = undefined,
    new_word_def: i32 = -888,

    pub fn init(self: *Forth, allocator: Allocator, console: *fbcons.FrameBufferConsole) !void {
        self.console = console;
        self.stack = DataStack.init(allocator);
        self.rstack = ReturnStack.init(allocator);
        self.dictionary = ValueDictionary.init(allocator);
        try core.defineCore(self);
        try core.wordClearScreen(self);
        //try self.evalBuffer(init_f);
    }

    pub fn print(self: *Forth, comptime fmt: []const u8, args: anytype) !void {
        try self.console.print(fmt, args);
    }

    pub fn writer(self: *Forth) fbcons.FrameBufferConsole.Writer {
        return self.console.writer();
    }

    pub fn evalFP(self: *Forth, v: Value) dict.ForthError!void {
        const fp =  v.extractFunction();
        try fp(self);
    }

    pub fn addToDefinition(self: *Forth, v: Value) void {
        self.memory[@intCast(self.nextFree)] = v;
        self.nextFree += 1;
    }

    pub fn _evalValue(self: *Forth, v: Value) !void {
        const vt = v.typeOf();
        switch (vt) {
            .word => {
                const name = v.extractWord();
                try self.print("eval word {any}\n", .{name});
                const assoc_value = try self.dictionary.get(name.*);
                try evalValue(self, assoc_value);
            },
            .function => {
                const wordf = v.extractFunction();
                try wordf(self);
            },
            .call => {
                const location = v.extractCall();
                try inner(self, location);
            },
            else => {
                try self.stack.push(v);
            },
        }
    }

    pub fn evalValue(self: *Forth, v: Value) ForthError!void {
        try self.print("eval value {any}\n", .{v});
        const t = v.typeOf();
        switch (t) {
            .word => {
                const name = v.extractWord();
                try self.print("Name: {any}!!!\n\n", .{name});
                const entry = try self.dictionary.getEntry(name.*);
                try self.print("word: {any} entry: {any}\n", .{ name, entry });
                if (entry.immediate) {
                    try _evalValue(self, entry.value);
                } else if (self.composing) {
                    self.addToDefinition(entry.value);
                } else {
                    try _evalValue(self, entry.value);
                }
            },
            .function => {
                if (self.composing) {
                    self.addToDefinition(v);
                } else {
                    const wordf = v.extractFunction();
                    try wordf(self);
                }
            },
            .call => {
                if (self.composing) {
                    self.addToDefinition(v);
                } else {
                    try inner(self, v.extractCall());
                }
            },
            else => |_| {
                if (self.composing) {
                    self.addToDefinition(v);
                } else {
                    try self.stack.push(v);
                }
            },
        }
    }
    fn define(self: *Forth, name: []const u8, v: Value, immediate: bool) !void {
        try self.dictionary.put(name, v, immediate);
    }

    pub fn definePrimitive(self: *Forth, name: []const u8, fp: WordFunction, immediate: bool) !void {
        try self.print("defining prim: [{s}]\n", .{name});
        const v = Value.mkFunction(fp);
        try self.define(name, v, immediate);
    }

    pub fn defineSecondary(self: *Forth, name: []const u8, address: i32) !void {
        // try self.print("define secondary {s} {}\n", .{ name, address });
        const v = Value.mkCall(address);
        try self.define(name, v, false);
    }

    pub fn defineVariable(self: *Forth, name: []const u8, v: Value) !void {
        try self.define(name, v, false);
    }

    fn emitPrompt(self: *Forth, prompt: []const u8) void {
        self.console.emitString(prompt);
    }

    fn readline(self: *Forth, buffer: []u8) !usize {
        var i: usize = 0;
        var ch: u8 = 0;

        while (i < (buffer.len - 1) and !newline(ch)) {
            ch = self.getc();
            self.putc(ch);

            switch (ch) {
                0x7f => if (i > 0) {
                    i -= 1;
                },
                else => {
                    buffer[i] = ch;
                    i += 1;
                },
            }
            buffer[i] = 0;
        }
        return i;
    }

    pub fn getc(self: *Forth) u8 {
        _ = self;
        var ch = bsp.io.receive();
        return if (ch == '\r') '\n' else ch;
    }

    pub fn char_available(self: *Forth) bool {
        _ = self;
        return bsp.io.byte_available();
    }

    pub fn putc(self: *Forth, ch: u8) void {
        bsp.io.send(ch);
        self.console.emit(ch);
    }

    pub fn repl(self: *Forth) !void {
        // outer loop, one line at a time.


        while (true) {
            self.emitPrompt("OK>> ");
            var line_len: usize = self.readline(&self.line_buffer) catch 0;

            self.words = ForthTokenIterator.init(self.line_buffer[0..line_len]);

            // inner loop, one word at a time.
            var word = self.words.next();
            while (word != null) : (word = self.words.next()) {
                if (word) |w| {
                    var v = Value.fromString(w) catch |err| {
                        try self.print("Parse error({s}): {}\n", .{ w, err });
                        continue;
                    };
                    self.evalValue(v) catch |err| {
                        try self.print("error: {any}\n", .{err});
                    };
                }
            }
        }
    }

    /// Evaluate a (potentially large) buffer of code. Mainly used for
    /// loading init.f
    pub fn evalBuffer(self: *Forth, buffer: []const u8) !void {
        self.words = ForthTokenIterator.init(buffer);

        // inner loop, one word at a time.
        var word = self.words.next();
        while (word != null) : (word = self.words.next()) {
            if (word) |w| {
                var v = Value.fromString(w) catch |err| {
                    try self.print("Parse error({s}): {}\n", .{ w, err });
                    continue;
                };
                self.evalValue(v) catch |err| {
                    try self.print("error: {any}\n", .{err});
                };
            }
        }

        self.words = undefined;
    }
};

pub fn inner(self: *Forth, address: i32) ForthError!void {
    try self.rstack.push(self.nexti);
    self.nexti = address;
    // try forth.print("start loop: {}\n", .{forth.nexti});
    while (self.nexti >= 0) {
        // try forth.print("inner loop: {}\n", .{forth.nexti});
        var v = self.memory[@intCast(self.nexti)];
        self.nexti += 1;
        self._evalValue(v) catch |err| {
            try self.print("Error: {any}\n", .{err});
            break;
        };
    }
    self.nexti = try self.rstack.pop();
}

fn newline(ch: u8) bool {
    return ch == '\r' or ch == '\n';
}
