const std = @import("std");
const mem = std.mem;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

//const WordFunction = @import("forth.zig").WordFunction;
const WordFunction = *const fn(x: i32) i32;

pub const ValueType = enum(u32) {
    function = 0x00, // *WordFunction
    call = 0x01, // i32
    address = 0x02, // u64 (actually u61)
    word = 0x03, // [*:0]const u8
    signed = 0x04, // i32
    unsigned = 0x05, // u32
    character = 0x06, // u8
    float = 0x07, // f32
    string = 0xf0, // string reference.
    string_data = 0xf1, // Beginning of string data.
};

const TypeMask: u64 = 0xff_00_00_00_00_00_00_00;
const DataMask = ~TypeMask;
const TypeShift: u64 = 56;

pub const Value = packed struct {
    data: u64,

    pub fn init(t: ValueType, i: u64) Value {
        var data: u64 = @intFromEnum(t);
        data = data << TypeShift; 
        data = data | (i & DataMask);
        return Value{.data = data};
    }

    pub inline fn typeOf(v: Value) ValueType {
        return @enumFromInt(v.extractTypeInt());
    }

    pub fn fromString(token: []const u8) ForthError!Value {
        if (token[0] == '"') {
            return Value.mkString(token[1..(token.len - 1)]);

        } else if (token[0] == '\\') {
            return Value.mkCharacter(token[1]);

        } else if (token[0] == '0' and token[1] == 'x') {
            var sNumber = token[2..];
            const uValue = std.fmt.parseInt(u32, sNumber, 16) catch {
                return ForthError.ParseError;
            };
            return Value.mkUnsigned(uValue);
        }
 
        var iValue = std.fmt.parseInt(i32, token, 10) catch {
            var fValue = std.fmt.parseFloat(f32, token) catch {
                return Value.mkWord(&token);
            };
            return Value.mkFloat(fValue);
        };
        return Value.mkSigned(iValue); 
    }

    // Functions

    pub inline fn mkFunction(x: WordFunction) Value {
        return init(ValueType.function, @intFromPtr(x));
    }

    // Gets the value of a function pointer. Does not check the type.
    pub fn extractFunction(v: Value) WordFunction {
        var i: u64  = v.extractDataInt();
        return @ptrFromInt(i);
    }

    // Calls

    pub fn mkCall(x: i32) Value {
        return init(ValueType.call, @as(u64, @intCast(x)));
    }

    // Gets the value of a call. Does not check the type.
    pub fn extractCall(v: Value) i32 {
        var i = v.extractDataInt();
        return @as(i32, @intCast(i));
    }

    // Address

    pub fn mkAddress(x: u64) Value {
        return init(ValueType.address, x);
    }

    // Gets the value of a address value. Does not check the type.
    pub inline fn extractAddress(v: Value) u64 {
        return v.extractDataInt();
    }

    // String

    pub fn mkString(x: [*]const u8) Value {
        var i = @as(u64, @intFromPtr(x));
        return init(ValueType.string, i);
    }

    // Gets the value of a address value. Does not check the type.
    pub inline fn extractString(v: Value) [*]u8 {
        return @ptrFromInt(extractDataInt(v));
    }

//    // Word
//
//    pub fn mkWord(x: [*]const u8) Value {
//        var i = @as(u64, @intFromPtr(x));
//        return init(ValueType.word, i);
//    }
//
//    // Gets the value of a address value. Does not check the type.
//    pub inline fn extractWord(v: Value) [*]u8 {
//        return @ptrFromInt(extractDataInt(v));
//    }

    // Signed

    pub fn mkSigned(x: i32) Value {
        var i: u32 = @bitCast(x);
        var j: u64 = i;
        return init(ValueType.signed, j);
    }

    // Gets the value of a call. Does not check the type.
    pub fn extractSigned(v: Value) i32 {
        var i: u64 = extractDataInt(v);
        var j: u32 = @intCast(i);
        return @bitCast(j);
    }

    // Unsigned

    pub fn mkUnsigned(x: u32) Value {
        var i = @as(u64, @intCast(x));
        return init(ValueType.unsigned, i);
    }

    pub fn extractUnsigned(v: Value) u32 {
        var i = extractDataInt(v);
        return @as(u32, @intCast(i));
    }

    // Character

    pub fn mkCharacter(x: u8) Value {
        var i = @as(u64, @intCast(x));
        return init(ValueType.character, i);
    }

    pub fn extractCharacter(v: Value) u8 {
        var i = extractDataInt(v);
        return @as(u8, @intCast(i));
    }

    // Float

    pub fn mkFloat(x: f32) Value {
        var ptr_f = std.mem.asBytes(&x);
        var i: u64 = 0;
        var ptr_i: [*]u8 = std.mem.asBytes(&i);
        ptr_i[3] = ptr_f[3];
        ptr_i[2] = ptr_f[2];
        ptr_i[1] = ptr_f[1];
        ptr_i[0] = ptr_f[0];
        return init(ValueType.float, i);
    }

    pub fn extractFloat(v: Value) f32 {
        var i: u64 = extractDataInt(v);
        var ptr_i = std.mem.asBytes(&i);
        var f: f32 = 0.0;
        var ptr_f = std.mem.asBytes(&f);
        ptr_f[3] = ptr_i[3];
        ptr_f[2] = ptr_i[2];
        ptr_f[1] = ptr_i[1];
        ptr_f[0] = ptr_i[0];
        return f;
    }

    pub fn pr(v: Value, writer: anytype, hex: bool) !void {
        var base: u8 = if (hex) 16 else 10;
        const t = v.typeOf();
        try switch (t) {
            .function => writer.print("{x}", .{v.extractFunction()}),
            .call => writer.print("call: {}", .{v.extractCall()}),
            .address => writer.print("addr: {x}", .{v.extractAddress()}),
            .string => writer.print("{any}", .{v.extractString()}),
            .signed => std.fmt.formatInt(v.extractSigned(), base, .lower, .{}, writer.writer()),
            .unsigned => std.fmt.formatInt(v.extractUnsigned(), base, .lower, .{}, writer.writer()),
            .character => writer.print("\\{c}", .{v.extractCharacter()}),
            .word => writer.print("word: {any}", .{v.extractWord()}),
            .float => writer.print("float: {}", .{v.extractFloat()}),
        };
    }

    pub fn add(a: Value, b: Value) !Value {
        var ta: ValueType = a.typeOf();
        var tb: ValueType = b.typeOf();

        if (ta != tb) {
            return ForthError.BadOperation;
        }

        switch (ta) {
            .long, .address, .unsigned, .character => {
                const u64_a = a.extractDataInt();
                const u64_b = b.extractDataInt();
                return init(ta, u64_a + u64_b);
            },
            .call, .signed => {
                var i32_a = extractSigned(a);
                var i32_b = extractSigned(b);
                return init(ta, @intCast(i32_a + i32_b));
            },
            .float => return mkFloat(a.extractFloat() + b.extractFloat()),
            else => return ForthError.BadOperation,
        }
    }

    pub fn sub(a: Value, b: Value) !Value {
        var ta: ValueType = a.typeOf();
        var tb: ValueType = b.typeOf();

        if (ta != tb) {
            return ForthError.BadOperation;
        }

        switch (ta) {
            .long, .address, .unsigned, .character => {
                const u64_a = a.extractDataInt();
                const u64_b = b.extractDataInt();
                return init(ta, u64_a - u64_b);
            },
            .call, .signed => {
                var i32_a = extractSigned(a);
                var i32_b = extractSigned(b);
                return init(ta, @intCast(i32_a - i32_b));
            },
            .float => return mkFloat(a.extractFloat() - b.extractFloat()),
            else => return ForthError.BadOperation,
        }
    }

    // Lower level extraction.

    pub inline fn extractTypeInt(v: Value) u64 {
        return v.data >> TypeShift;
    }

    pub inline fn extractDataInt(v: Value) u64 {
        return v.data & DataMask;
    }
};

fn dummy(x: i32) i32 {
    return x + 1;
}

test "Value type extraction" {
    const assert = std.debug.assert;
    const print = std.debug.print;

    print("functions\n", .{});
    const vfunc = Value.mkFunction(&dummy);
    assert(vfunc.typeOf() == ValueType.function);
    assert(vfunc.extractFunction() == &dummy);

    print("call\n", .{});
    const vcall = Value.mkCall(3);
    print("call hex: {x}\n", .{vcall.data});
    assert(vcall.typeOf() == ValueType.call);
    assert(vcall.extractCall() == 3);

    print("addr\n", .{});
    const vaddress = Value.mkAddress(0xabcdabcd);
    assert(vaddress.typeOf() == ValueType.address);
    assert(vaddress.extractAddress() == 0xabcdabcd);

    print("string\n", .{});
    const s1: *const [3:0]u8 = "abc";
    //const s2: [*]u8 = @constCast(s1);
    const s2: [*]const u8 = s1.ptr;
    const vstring = Value.mkString(s2);
    assert(vstring.typeOf() == ValueType.string);
    const result = vstring.extractString();
    assert(result[0] == 'a');
    assert(result[1] == 'b');
    assert(result[2] == 'c');
    assert(result[3] == 0);

    print("signed (i32)\n", .{});
    var xsigned: i32 = 1234;
    var vsigned = Value.mkSigned(xsigned);
    assert(vsigned.typeOf() == ValueType.signed);
    assert(vsigned.extractSigned() == 1234);

    xsigned = -99999;
    vsigned = Value.mkSigned(xsigned);
    assert(vsigned.extractSigned() == -99999);

    print("float\n", .{});
    var xfloat: f32 = 3.14159;
    var vfloat = Value.mkFloat(xfloat);
    assert(vfloat.typeOf() == ValueType.float);
    print("returned value {}\n", .{vfloat.extractFloat()});
    assert(vfloat.extractFloat() == 3.14159);

    print("unsigned\n", .{});
    const vunsigned = Value.mkUnsigned(3);
    assert(vunsigned.typeOf() == ValueType.unsigned);
    assert(vunsigned.extractUnsigned() == 3);

    print("character\n", .{});
    const vcharacter = Value.mkCharacter('X');
    assert(vcharacter.typeOf() == ValueType.character);
    assert(vcharacter.extractCharacter() == 'X');
}
