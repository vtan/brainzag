const std = @import("std");
const bf = @import("bf.zig");

pub const Code = struct {
    const Self = @This();

    mmap_region: []u8,

    pub fn init(code: []u8) !Self {
        // mprotect expects mmap_region.len to be a multiple of the page size
        const len = (code.len / std.mem.page_size + 1) * std.mem.page_size;
        var mmap_region = try std.os.mmap(
            null,
            len,
            std.os.PROT.READ | std.os.PROT.WRITE,
            std.os.MAP.ANONYMOUS | std.os.MAP.PRIVATE,
            -1,
            0,
        );
        @memcpy(mmap_region[0..code.len], code);

        try std.os.mprotect(mmap_region, std.os.PROT.READ | std.os.PROT.EXEC);

        return Self{ .mmap_region = mmap_region };
    }

    pub fn deinit(self: *Self) void {
        std.os.munmap(self.mmap_region);
    }

    pub fn run(self: *const Self, tape: []u8) void {
        const Env = packed struct {
            write: *const fn (u8) callconv(.C) void,
            read: *const fn () callconv(.C) u8,
        };

        var env = Env{ .write = undefined, .read = undefined };
        env.write = envWrite;
        env.read = envRead;

        const f: *const fn (*u8, *const Env) callconv(.C) void = @alignCast(@ptrCast(self.mmap_region.ptr));
        var tape_pointer = &tape[bf.TAPE_SIZE / 2];
        f(tape_pointer, &env);
    }

    fn envWrite(ch: u8) callconv(.C) void {
        std.io.getStdOut().writeAll(
            &[1]u8{ch},
        ) catch unreachable;
    }

    fn envRead() callconv(.C) u8 {
        var buf: [1]u8 = undefined;
        const read_count = std.io.getStdIn().read(&buf) catch return 0;
        if (read_count == 0) {
            return 0;
        } else {
            return buf[0];
        }
    }
};

pub const Builder = struct {
    const Self = @This();

    bytes: std.ArrayList(u8),

    pub fn init() Self {
        return Self{
            .bytes = std.ArrayList(u8).init(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.deinit();
    }

    pub fn len(self: *const Self) usize {
        return self.bytes.items.len;
    }

    pub fn emit(self: *Self, bytes: []const u8) !void {
        try self.bytes.appendSlice(bytes);
    }

    pub fn emit8(self: *Self, x: u8) !void {
        try self.bytes.append(x);
    }

    pub fn emit32(self: *Self, x: i32) !void {
        const u: u32 = @bitCast(x);
        try self.bytes.appendSlice(&[_]u8{
            @truncate(u),
            @truncate(u >> 8),
            @truncate(u >> 16),
            @truncate(u >> 24),
        });
    }

    pub fn fill32(self: *Self, offset: usize, x: i32) void {
        const u: u32 = @bitCast(x);
        self.bytes.items[offset] = @truncate(u);
        self.bytes.items[offset + 1] = @truncate(u >> 8);
        self.bytes.items[offset + 2] = @truncate(u >> 16);
        self.bytes.items[offset + 3] = @truncate(u >> 24);
    }

    pub fn build(self: *const Self) !Code {
        return Code.init(self.bytes.items);
    }
};
