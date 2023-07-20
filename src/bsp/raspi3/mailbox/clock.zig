const mailbox = @import("../mailbox.zig");
const Message = mailbox.Message;
const Envelope = mailbox.Envelope;

const ClockMessage = struct {
    const Self = @This();
    clock_type: ClockRate.Clock,
    rate: u32 = 0,

    pub fn init(clock_type: ClockRate.Clock) Self {
        return Self{
            .clock_type = clock_type,
        };
    }

    pub fn message(self: *Self) Message {
        return Message.init(self, .RPI_FIRMWARE_GET_CLOCK_RATE, 1, 2, fill, unfill);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = @intFromEnum(self.clock_type);
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.clock_type = @enumFromInt(buf[0]);
        self.rate = buf[1];
    }
};

pub const ClockRate = packed struct {
    pub const Clock = enum(u32) {
        emmc = 1,
        uart = 2,
        arm = 3,
        core = 4,
    };

    clock_type: Clock,
    rate: u32,
};

pub fn get_clock_rate(clock_type: ClockRate.Clock) !struct { bool, u32 } {
    var clockmsg = ClockMessage.init(clock_type);
    var messages = [_]Message{clockmsg.message()};
    var env = Envelope.init(&messages);

    _ = try env.call();

    return .{ true, clockmsg.rate };
}
