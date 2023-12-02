const std = @import("std");
const bf = @import("bf.zig");
const jit = @import("jit.zig");

pub fn gen(ops: []const bf.Op, builder: *jit.Builder) !void {
    try genPrologue(builder);

    var jump_offsets = std.ArrayList(i32).init(std.heap.page_allocator);
    defer jump_offsets.deinit();

    for (ops) |op| {
        switch (op) {
            .add => |amount| {
                _ = amount;
            },

            .move => |amount| {
                _ = amount;
            },

            .jump_if_zero => {},

            .jump_back_if_non_zero => {},

            .write => {},

            .read => {},
        }
    }

    try genEpilogue(builder);
}

pub fn genPrologue(builder: *jit.Builder) !void {
    _ = builder;
}

pub fn genEpilogue(builder: *jit.Builder) !void {
    try builder.emit32s(&[_]u32{
        // jalr zero, ra, 0
        jalr(Regs.zero, Regs.return_addr, 0),
    });
}

const Reg = u5;

const Regs = struct {
    pub const zero: Reg = 0;
    pub const return_addr: Reg = 1;
};

fn jalr(dest: Reg, src: Reg, offset: i12) u32 {
    return encode_i(0b1100111, 0, dest, src, @bitCast(offset));
}

fn encode_i(opcode: u7, funct3: u3, rd: Reg, rs1: Reg, imm: u12) u32 {
    return @as(u32, opcode) |
        (@as(u32, rd) << 7) |
        (@as(u32, funct3) << 12) |
        (@as(u32, rs1) << 15) |
        (@as(u32, imm) << 20);
}
