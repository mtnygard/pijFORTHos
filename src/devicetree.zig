const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const root = @import("root");

// This symbol is defined in boot.S.
// At boot time its value will be supplied by the firmware, which will
// point it at some memory.
pub extern var __fdt_address: usize;

pub const Fdt = struct {
    const Self = @This();

    const NodeList = ArrayList(*Node);
    const PropertyList = ArrayList(*Property);

    // These constants come from the device tree specification.
    // See https://github.com/devicetree-org/devicetree-specification
    const compatible_version = 16;
    const magic_value = 0xd00dfeed;
    pub const tag_size: usize = @sizeOf(u32);

    // Member variables will be in native byte order
    struct_base: usize = undefined,
    struct_size: usize = undefined,
    strings_base: usize = undefined,
    strings_size: usize = undefined,

    root_node: *Node = undefined,

    pub const Error = error{
        OutOfMemory,
        NotFound,
        BadVersion,
        BadTagAlignment,
        IncorrectTag,
        NoTagAtOffset,
        BadContents,
    };

    /// Note: when reading from the fdt blob, these will all be
    /// big-endian
    ///
    /// Struct definition comes from the device tree specification
    const Header = extern struct {
        magic: u32,
        total_size: u32,
        off_dt_struct: u32,
        off_dt_strings: u32,
        off_mem_rsvmap: u32,
        version: u32,
        last_compatible_version: u32,
        boot_cpuid_physical: u32,
        size_dt_strings: u32,
        size_dt_struct: u32,
    };

    pub fn init(self: *Fdt, allocator: Allocator) !void {
        try self.initFromPointer(allocator, __fdt_address);
    }

    pub fn initFromPointer(self: *Fdt, allocator: Allocator, fdt_address: u64) !void {
        var h: *Header = @ptrFromInt(fdt_address);

        if (nativeByteOrder(h.magic) != magic_value) {
            return Error.NotFound;
        }

        if (nativeByteOrder(h.last_compatible_version) < compatible_version) {
            return Error.BadVersion;
        }

        // if those passed, we have a good blob.
        // from here, self.struct_base and self.strings_base will be
        // pre-added and in native byte order
        self.struct_base = fdt_address + nativeByteOrder(h.off_dt_struct);
        self.struct_size = nativeByteOrder(h.size_dt_struct);
        self.strings_base = fdt_address + nativeByteOrder(h.off_dt_strings);
        self.strings_size = nativeByteOrder(h.size_dt_strings);

        self.root_node = try parse(self, allocator);
    }

    pub fn deinit(self: *Fdt) void {
        self.root_node.deinit();
    }

    pub fn nodeLookupByPath(self: *Fdt, path: [:0]const u8) !?*Node {
        return self.root_node.lookupChildByPath(path, 0, path.len);
    }

    pub const TokenType = enum(u32) {
        beginNode = 0x00000001,
        endNode = 0x00000002,
        property = 0x00000003,
        nop = 0x00000004,
        end = 0x00000009,
    };

    pub const Node = struct {
        allocator: Allocator,

        fdt: *Fdt = undefined,
        offset: u64 = undefined,
        name: []const u8 = undefined,
        parent: *Node = undefined,
        children: NodeList,
        properties: PropertyList,

        pub fn create(allocator: Allocator, fdt: *Fdt, offset: u64, name: []const u8) Error!*Node {
            var current_tag_type = try fdt.tagTypeAt(offset);

            if (current_tag_type != .beginNode) {
                return Fdt.Error.IncorrectTag;
            }

            var node: *Node = try allocator.create(Node);
            node.* = Node{
                .allocator = allocator,
                .fdt = fdt,
                .offset = offset,
                .name = name,
                .children = NodeList.init(allocator),
                .properties = PropertyList.init(allocator),
            };
            return node;
        }

        pub fn deinit(self: *Node) void {
            for (self.properties.items) |p| {
                p.deinit();
            }
            self.properties.deinit();

            for (self.children.items) |n| {
                n.deinit();
            }
            self.children.deinit();
            self.allocator.destroy(self);
        }

        pub fn getChildByName(self: *Node, name: []const u8) ?*Node {
            for (self.children.items) |c| {
                if (std.mem.eql(u8, c.name, name)) {
                    return c;
                }
            }
            return null;
        }

        pub fn lookupChildByPath(self: *Node, path: [:0]const u8, start: usize, end: usize) ?*Node {
            // TODO: handle aliases

            if (start == end) {
                return self;
            }

            // pointer to start of current path segment
            var p: usize = start;
            // pointer to end of current path segment
            var q: usize = start;

            // Walk the path, one segment at a time. For each segment,
            // look for a subnode of the current node.

            // Skip the path separator
            while (path[p] == '/') {
                p += 1;
                // If the path ended with '/', we're at the intended
                // node
                if (p == end) {
                    return self;
                }
            }

            // find the next separator, or if none use all of the
            // remaining string as the node name
            q = charIndex('/', path, p) orelse end;

            // starting from the current offset, locate a subnode with
            // the desired name
            if (self.getChildByName(path[p..q])) |child| {
                return child.lookupChildByPath(path, q, end);
            } else {
                return null;
            }
        }
    };

    pub const Property = struct {
        allocator: Allocator,
        offset: u64 = undefined,
        value_offset: u64 = undefined,
        value_len: usize = undefined,
        name: [*:0]u8 = undefined,
        owner: *Node = undefined,

        pub fn create(allocator: Allocator, owner: *Node, offset: u64, name: [*:0]u8, value_offset: u64, value_len: usize) Error!*Property {
            var prop = try allocator.create(Property);
            prop.* = Property{
                .allocator = allocator,
                .offset = offset,
                .owner = owner,
                .name = name,
                .value_offset = value_offset,
                .value_len = value_len,
            };
            return prop;
        }

        pub fn deinit(self: *Property) void {
            self.allocator.destroy(self);
        }
    };

    pub fn parse(self: *Fdt, allocator: Allocator) !*Node {
        var parents = NodeList.init(allocator);
        defer parents.deinit();

        var current_tag_offset: usize = 0;

        var current_tag_type = try self.tagTypeAt(current_tag_offset);
        if (current_tag_type != .beginNode) {
            return Fdt.Error.IncorrectTag;
        }

        // walk the tags.
        while (current_tag_offset < self.struct_size) {
            // std.debug.print("{x:0>5} {s}\n", .{ current_tag_offset, @tagName(current_tag_type) });

            switch (current_tag_type) {
                .beginNode => {
                    const node_offset = current_tag_offset;

                    // locate the name
                    current_tag_offset += tag_size;
                    var p: [*]u8 = @ptrCast(self.ptrFromOffset(u8, current_tag_offset));
                    current_tag_offset += 1;
                    var i: usize = 0;
                    while (p[i] != 0) : (i += 1) {}
                    current_tag_offset += i;
                    const node_name = p[0..i];

                    //   create new Node object with that as offset
                    const node = try Node.create(allocator, self, node_offset, node_name);

                    //   add it as a child to the Node on top of `parents`
                    if (parents.getLastOrNull()) |current_parent| {
                        try current_parent.children.append(node);
                    }

                    // std.debug.print(">>\n", .{});

                    //   push the new Node onto parents
                    try parents.append(node);
                },
                .endNode => {
                    // advance offset past the tag. the tag has no body.
                    current_tag_offset += tag_size;

                    // std.debug.print("<<\n", .{});

                    //   pop the top of `parents`
                    if (parents.popOrNull()) |current_node| {
                        if (parents.items.len == 0) {
                            // if the stack is now empty, we've reached
                            // the final .endNode, return the root node
                            return current_node;
                        }
                    } else {
                        // we've seen more .endNode tags than .beginNode
                        return Fdt.Error.BadContents;
                    }
                },
                .end => {
                    return Fdt.Error.BadContents;
                },
                .property => {
                    const prop_offset = current_tag_offset;

                    current_tag_offset += tag_size;
                    const value_len = self.valueAtOffset(u32, current_tag_offset);

                    current_tag_offset += tag_size;
                    const prop_name_idx = self.valueAtOffset(u32, current_tag_offset);

                    current_tag_offset += tag_size;
                    const value_offset = current_tag_offset;

                    current_tag_offset += value_len;

                    const current_parent = parents.getLastOrNull();

                    if (current_parent == null) {
                        return Error.BadContents;
                    }

                    const prop_name = self.stringAt(prop_name_idx);
                    const prop = try Property.create(allocator, current_parent.?, prop_offset, prop_name, value_offset, value_len);

                    try current_parent.?.properties.append(prop);
                },
                inline else => current_tag_offset += tag_size,
            }

            current_tag_offset = std.mem.alignForward(usize, current_tag_offset, tag_size);
            current_tag_type = try self.tagTypeAt(current_tag_offset);
        }

        // We've walked past the end of the struct but didn't see matching
        // .endNode tag
        return Error.BadContents;
    }

    pub fn tagTypeAt(self: *Fdt, tag_offset: usize) !TokenType {
        if (0 != (tag_offset % tag_size)) {
            return Error.BadTagAlignment;
        }

        var tag_ptr: *u32 = self.ptrFromOffset(u32, tag_offset);
        var tag: u32 = nativeByteOrder(tag_ptr.*);
        switch (tag) {
            0x00000001 => return .beginNode,
            0x00000002 => return .endNode,
            0x00000003 => return .property,
            0x00000004 => return .nop,
            0x00000009 => return .end,
            else => {
                // std.debug.print("At offset {x}, found {x} instead of a device tree tag\n", .{ tag_offset, tag });
                return Error.NoTagAtOffset;
            },
        }
    }

    inline fn stringAt(self: *Fdt, string_offset: usize) [*:0]u8 {
        var string_addr = self.strings_base + string_offset;
        return @ptrFromInt(string_addr);
    }

    inline fn ptrFromOffset(self: *Fdt, comptime T: type, offset: usize) *T {
        // var base: usize = self.struct_base + offset;
        return @ptrFromInt(self.struct_base + offset);
    }

    inline fn valueAtOffset(self: *Fdt, comptime T: type, offset: usize) T {
        const p: *T = self.ptrFromOffset(T, offset);
        return nativeByteOrder(p.*);
    }
};

inline fn nativeByteOrder(v: u32) u32 {
    return std.mem.bigToNative(u32, v);
}

fn charIndex(ch: u8, s: [:0]const u8, from: usize) ?usize {
    for (from..s.len) |i| {
        if (s[i] == ch) {
            return i;
        }
    }
    return null;
}

test "locate node by path" {
    const fdt_path = "test/resources/fdt.bin";
    const stat = try std.fs.cwd().statFile(fdt_path);
    var buffer = try std.fs.cwd().readFileAlloc(std.testing.allocator, fdt_path, stat.size);
    defer std.testing.allocator.free(buffer);

    var fdt = Fdt{};
    try fdt.initFromPointer(std.testing.allocator, @intFromPtr(buffer.ptr));
    defer fdt.deinit();

    const print = std.debug.print;
    const expectEqualStrings = std.testing.expectEqualStrings;

    print("\n", .{});

    var devtree_root = fdt.root_node;

    try expectEqualStrings("", devtree_root.name);

    var found = try fdt.nodeLookupByPath("thermal-zones/cpu-thermal/cooling-maps");
    print("{s} @ {d}\n", .{ found.?.name, found.?.offset });
}
