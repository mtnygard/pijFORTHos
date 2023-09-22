const std = @import("std");
const assert = std.debug.assert;

const hal = @import("hal.zig");
const common = hal.common;
const DMAController = hal.common.DMAController;
const DMAChannel = hal.common.DMAChannel;
const DMARequest = hal.common.DMARequest;

const Region = @import("memory.zig").Region;

pub const FrameBuffer = struct {
    dma: *DMAController = undefined,
    dma_channel: ?DMAChannel = undefined,
    base: [*]u8 = undefined,
    buffer_size: usize = undefined,
    pitch: usize = undefined,
    xres: usize = undefined,
    yres: usize = undefined,
    bpp: u32 = undefined,
    range: Region = Region{ .name = "Frame Buffer" },

    pub fn fillRegion(self: *FrameBuffer, x: usize, y: usize, w: usize, h: usize, color: u8) void {
        // fast path if filling the whole framebuffer
        if (x == 0 and y == 0 and w == self.xres and h == self.yres) {
            for (0..self.buffer_size) |i| {
                self.base[i] = color;
            }
        } else {
            var line_stride = self.pitch;
            var fbidx = x + (y * line_stride);
            var line_step = line_stride - w;
            for (0..h) |_| {
                for (0..w) |_| {
                    self.base[fbidx] = color;
                    fbidx += 1;
                }
                fbidx += line_step;
            }
        }
    }

    pub fn blit(fb: *FrameBuffer, src_x: usize, src_y: usize, src_w: usize, src_h: usize, dest_x: usize, dest_y: usize) void {
        if (fb.dma_channel) |ch| {
            // TODO: probably ought to clip some of these values to
            // make sure they're all inside the framebuffer!
            const fb_base: usize = @intFromPtr(fb.base);
            const fb_pitch = fb.pitch;
            const stride_2d = fb.xres - src_w;
            const xfer_y_len = src_h;
            const xfer_x_len = src_w;

            const len = if (stride_2d > 0) ((xfer_y_len << 16) + xfer_x_len) else (src_h * fb.xres);

            var req = DMARequest{
                .source = fb_base + (src_y * fb_pitch) + src_x,
                .destination = fb_base + (dest_y * fb_pitch) + dest_x,
                .length = len,
                .stride = (stride_2d << 16) | stride_2d,
            };
            fb.dma.initiate(ch, &req) catch {};
            _ = fb.dma.awaitChannel(ch);
        }
    }
};
