const std = @import("std");

pub const Code = struct {
    const Self = @This();

    mmap_region: []u8,

    pub fn init(code: []u8) !Self {
        var mmap_region = try std.os.mmap(
            null,
            code.len,
            std.os.PROT.READ | std.os.PROT.WRITE | std.os.PROT.EXEC,
            std.os.MAP.ANONYMOUS | std.os.MAP.PRIVATE,
            -1,
            0,
        );
        @memcpy(mmap_region, code);

        // TODO: mprotect expects mmap_region.len to be page-aligned, why?
        // try std.os.mprotect(mmap_region, std.os.PROT.READ | std.os.PROT.EXEC);

        return Self{ .mmap_region = mmap_region };
    }

    pub fn deinit(self: *Self) void {
        std.os.munmap(self.mmap_region);
    }

    pub fn run(self: *const Self) void {
        const Env = packed struct {
            print: *const fn (u8) callconv(.C) void,
        };

        var env = Env{ .print = undefined };
        env.print = envPrint;

        const f: *const fn (u64, *const Env) callconv(.C) void = @ptrCast(self.mmap_region.ptr);
        f(0x42, &env);
    }

    fn envPrint(ch: u8) callconv(.C) void {
        std.io.getStdOut().writeAll(
            &[1]u8{ch},
        ) catch unreachable;
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

    pub fn emit(self: *Self, bytes: []const u8) !void {
        try self.bytes.appendSlice(bytes);
    }

    pub fn emit8(self: *Self, x: u8) !void {
        try self.bytes.append(x);
    }

    pub fn build(self: *Self) !Code {
        return Code.init(self.bytes.items);
    }
};
