const std = @import("std");

const Forth = @import("../forty/forth.zig").Forth;

const root = @import("root");
const Mailbox = root.HAL.Mailbox;
const PropertyTag = root.HAL.Mailbox.PropertyTag;
const RpiFirmwarePropertyTag = root.HAL.Mailbox.RpiFirmwarePropertyTag;

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(PeripheralClockController, .{
        .{ "clockRateCurrent", "clock-rate" },
        .{ "clockRateMax", "clock-rate-max" },
        .{ "clockRateMin", "clock-rate-min" },
        .{ "clockRateSet", "clock-set-rate" },
        .{ "clockStateSet", "clock-set-state" },
        .{ "clockState", "clock-state" },
        .{ "clockOn", "clock-on" },
        .{ "clockOff", "clock-off" },
    });
}

pub const clock_reserved: u32 = 0;
pub const clock_emmc: u32 = 1;
pub const clock_uart: u32 = 2;
pub const clock_arm: u32 = 3;
pub const clock_core: u32 = 4;
pub const clock_v3d: u32 = 5;
pub const clock_h264: u32 = 6;
pub const clock_isp: u32 = 7;
pub const clock_sdram: u32 = 8;
pub const clock_pixel: u32 = 9;
pub const clock_pwm: u32 = 10;

pub const state_off: u32 = 0;
pub const state_on: u32 = 1;

pub const ClockResult = enum(u64) {
    unknown = 0,
    failed = 1,
    no_such_device = 2,
    clock_on = 3,
    clock_off = 4,
};

const PropertyClock = extern struct {
    tag: PropertyTag,
    clock: u32,
    param2: u32,

    pub fn initStateQuery(clock: u32) @This() {
        return .{
            .tag = PropertyTag.init(RpiFirmwarePropertyTag.rpi_firmware_get_clock_state, 1, 2),
            .clock = clock,
            .param2 = 0,
        };
    }

    pub fn initStateControl(clock: u32, desired_state: u32) @This() {
        return .{
            .tag = PropertyTag.init(RpiFirmwarePropertyTag.rpi_firmware_set_clock_state, 2, 2),
            .clock = clock,
            .param2 = desired_state,
        };
    }

    pub fn initRateQuery(clock: u32, rate_selector: u32) @This() {
        return .{
            .tag = PropertyTag.init(rate_selector, 1, 2),
            .clock = clock,
            .param2 = 0,
        };
    }
};

const PropertyClockRateControl = extern struct {
    tag: PropertyTag,
    clock: u32,
    rate: u32,
    skip_turbo: u32,

    pub fn initRateControl(clock: u32, desired_rate: u32) @This() {
        return .{
            .tag = PropertyTag.init(RpiFirmwarePropertyTag.rpi_firmware_set_clock_rate, 3, 2),
            .clock = clock,
            .rate = desired_rate,
            .skip_turbo = 1,
        };
    }
};

pub const PeripheralClockController = struct {
    mailbox: *Mailbox,

    pub fn init(mailbox: *Mailbox) PeripheralClockController {
        return .{
            .mailbox = mailbox,
        };
    }

    fn decode(state: u32) ClockResult {
        const no_device = (state & 0x02) != 0;
        const actual_state = (state & 0x01) != 0;

        if (no_device) {
            return .no_such_device;
        } else if (actual_state) {
            return .clock_on;
        } else {
            return .clock_off;
        }
    }

    fn clockRate(self: *PeripheralClockController, clock_id: u32, selector: u32) !u32 {
        var query = PropertyClock.initRateQuery(clock_id, selector);
        try self.mailbox.getTag(&query);
        return query.param2;
    }

    pub fn clockRateCurrent(self: *PeripheralClockController, clock_id: u32) !u32 {
        return self.clockRate(clock_id, RpiFirmwarePropertyTag.rpi_firmware_get_clock_rate);
    }

    pub fn clockRateMax(self: *PeripheralClockController, clock_id: u32) !u32 {
        return self.clockRate(clock_id, RpiFirmwarePropertyTag.rpi_firmware_get_max_clock_rate);
    }

    pub fn clockRateMin(self: *PeripheralClockController, clock_id: u32) !u32 {
        return self.clockRate(clock_id, RpiFirmwarePropertyTag.rpi_firmware_get_min_clock_rate);
    }

    pub fn clockRateSet(self: *PeripheralClockController, clock_id: u32, desired_rate: u32) !u32 {
        const control = PropertyClockRateControl.initRateControl(clock_id, desired_rate);
        try self.mailbox.getTag(&control);
        return control.rate;
    }

    pub fn clockStateSet(self: *PeripheralClockController, clock_id: u32, desired_state: u32) !ClockResult {
        const control = PropertyClock.initStateControl(clock_id, desired_state);
        try self.mailbox.getTag(&control);
        return decode(control.param2);
    }

    pub fn clockState(self: *PeripheralClockController, clock_id: u32) !ClockResult {
        const query = PropertyClock.initStateQuery(clock_id);
        try self.mailbox.getTag(&query);
        return decode(query.clock);
    }

    pub fn clockOn(self: *PeripheralClockController, clock_id: u32) !ClockResult {
        return self.clockStateSet(clock_id, state_on);
    }

    pub fn clockOff(self: *PeripheralClockController, clock_id: u32) !ClockResult {
        return self.clockStateSet(clock_id, state_off);
    }
};
