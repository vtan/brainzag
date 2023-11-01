const std = @import("std");
const bf = @import("bf.zig");
const jit = @import("jit.zig");

// x19: tape pointer
// x20: pointer to external functions
// x0: function arg 1
// x1: function arg 2

pub fn gen(ops: []const bf.Op, builder: *jit.Builder) !void {
    try genPrologue(builder);

    var forward_jump_offsets = std.AutoHashMap(u32, i32).init(std.heap.page_allocator);
    defer forward_jump_offsets.deinit();

    for (ops, 0..) |op, i| {
        switch (op) {
            .add => |amount| {
                // ldrb w0, [x19]
                try builder.emit32(0x3940_0260);

                // add w0, w0, amount
                const signed_imm: i12 = @intCast(amount);
                const imm: u12 = @bitCast(signed_imm);
                try builder.emit32(0x1100_0000 | (@as(u32, imm) << 10));

                // strb w0, [x19]
                try builder.emit32(0x3900_0260);
            },

            .move => |amount| {
                // add x19, x19, amount
                const signed_imm: i12 = @intCast(amount);
                const imm: u12 = @bitCast(signed_imm);
                try builder.emit32(0x9100_0273 | (@as(u32, imm) << 10));
            },

            .jump_if_zero => {
                // ldrb w0, [x19]
                try builder.emit32(0x3940_0260);

                // ands wzr, w0, w0
                try builder.emit32(0x6a00_001f);

                try forward_jump_offsets.put(
                    @intCast(i),
                    @intCast(builder.len()),
                );

                // udf, to be filled by the matching jump back
                try builder.emit32(0x0000_dead);
            },

            .jump_back_if_non_zero => |dest| {
                const pair_offset = forward_jump_offsets.get(dest) orelse unreachable;

                // ldrb w0, [x19]
                try builder.emit32(0x3940_0260);

                // tst w0, w0
                try builder.emit32(0x6a00_001f);

                // b.ne dest
                const relative_offset: i19 = @intCast(((pair_offset + 4) - (@as(i32, @intCast(builder.len())))) >> 2);
                const unsigned_relative_offset: u19 = @bitCast(relative_offset);
                try builder.emit32(0x5400_0001 | (@as(u32, unsigned_relative_offset) << 5));

                // fill the matching jump:
                // b.eq $
                const relative_offset_back: i19 = @intCast((@as(i32, @intCast(builder.len())) - pair_offset) >> 2);
                const unsigned_relative_offset_back: u19 = @bitCast(relative_offset_back);
                builder.fill32(
                    @intCast(pair_offset),
                    0x5400_0000 | (@as(u32, unsigned_relative_offset_back) << 5),
                );
            },

            .write => {
                // ldrb w0, [x19]
                try builder.emit32(0x3940_0260);
                // ldur x1, [x20]
                try builder.emit32(0xf840_0281);
                // blr x1
                try builder.emit32(0xd63f_0020);
            },

            .read => unreachable,
        }
    }

    try genEpilogue(builder);
}

pub fn genPrologue(builder: *jit.Builder) !void {
    // stp x29, x30, [sp, -16]!
    try builder.emit32(0xA9BF_7BFD);
    // mov x29, sp
    try builder.emit32(0x9100_03FD);
    // mov x19, x0
    try builder.emit32(0xAA00_03F3);
    // mov x20, x1
    try builder.emit32(0xAA01_03F4);
}

pub fn genEpilogue(builder: *jit.Builder) !void {
    // ldp x29, x30, [sp], 16
    try builder.emit32(0xA8C1_7BFD);
    try builder.emit32(0xD65F_03C0);
}
