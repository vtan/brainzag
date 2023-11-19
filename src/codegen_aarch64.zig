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
                // ldrb w0, [x19]
                try builder.emit32(
                    load_reg32_byte(Regs.arg0, Regs.tape_ptr),
                );

                // add w0, w0, amount
                const amount12: i12 = @intCast(amount);
                try builder.emit32(
                    add32_immediate(Regs.arg0, Regs.arg0, @bitCast(amount12)),
                );

                // strb w0, [x19]
                try builder.emit32(
                    store_reg32_byte(Regs.arg0, Regs.tape_ptr),
                );
            },

            .move => |amount| {
                try builder.emit32(
                    if (amount >= 0)
                        // add x19, x19, amount
                        add64_immediate(Regs.tape_ptr, Regs.tape_ptr, @intCast(amount))
                    else
                        // sub x19, x19, -amount
                        sub64_immediate(Regs.tape_ptr, Regs.tape_ptr, @intCast(-amount)),
                );
            },

            .jump_if_zero => {
                // ldrb w0, [x19]
                try builder.emit32(
                    load_reg32_byte(Regs.arg0, Regs.tape_ptr),
                );

                // ands wzr, w0, w0
                try builder.emit32(
                    and32_flags(Regs.zero, Regs.arg0, Regs.arg0),
                );

                try jump_offsets.append(@intCast(builder.len()));

                // udf, to be filled by the matching jump back
                try builder.emit32(0x0000_dead);
            },

            .jump_back_if_non_zero => {
                const pair_offset = jump_offsets.pop();

                // ldrb w0, [x19]
                try builder.emit32(
                    load_reg32_byte(Regs.arg0, Regs.tape_ptr),
                );

                // ands wzr, w0, w0
                try builder.emit32(
                    and32_flags(Regs.zero, Regs.arg0, Regs.arg0),
                );

                // b.ne dest
                const relative_offset: i19 = @intCast((pair_offset + 4) - (@as(i32, @intCast(builder.len()))));
                try builder.emit32(
                    branch(Cond.not_equal, relative_offset),
                );

                // fill the matching jump:
                // b.eq $
                const relative_offset_back: i19 = @intCast(@as(i32, @intCast(builder.len())) - pair_offset);
                builder.fill32(
                    @intCast(pair_offset),
                    branch(Cond.equal, relative_offset_back),
                );
            },

            .write => {
                // ldrb w0, [x19]
                try builder.emit32(
                    load_reg32_byte(Regs.arg0, Regs.tape_ptr),
                );
                // ldur x1, [x20]
                try builder.emit32(
                    load_unscaled_reg64(Regs.arg1, Regs.env_ptr),
                );
                // blr x1
                try builder.emit32(
                    branch_link_reg(Regs.arg1),
                );
            },

            .read => {
                // add x1, x20, 8
                try builder.emit32(
                    add64_immediate(Regs.arg1, Regs.env_ptr, 8),
                );
                // ldur x1, [x1]
                try builder.emit32(
                    load_unscaled_reg64(Regs.arg1, Regs.arg1),
                );
                // blr x1
                try builder.emit32(
                    branch_link_reg(Regs.arg1),
                );
                // strb w0, [x19]
                try builder.emit32(
                    store_reg32_byte(Regs.arg0, Regs.tape_ptr),
                );
            },
        }
    }

    try genEpilogue(builder);
}

pub fn genPrologue(builder: *jit.Builder) !void {
    // stp x29, x30, [sp, -16]!
    try builder.emit32(
        store_pair64_pre_index(Regs.frame_ptr, Regs.link_reg, Regs.stack_ptr, -16),
    );
    // mov x29, sp
    try builder.emit32(
        or64(Regs.frame_ptr, Regs.zero, Regs.stack_ptr),
    );
    // mov x19, x0
    try builder.emit32(
        or64(Regs.tape_ptr, Regs.zero, Regs.arg0),
    );
    // mov x20, x1
    try builder.emit32(
        or64(Regs.env_ptr, Regs.zero, Regs.arg1),
    );
}

pub fn genEpilogue(builder: *jit.Builder) !void {
    // ldp x29, x30, [sp], 16
    try builder.emit32(
        load_pair64(Regs.frame_ptr, Regs.link_reg, Regs.stack_ptr, 16),
    );
    try builder.emit32(
        ret(Regs.link_reg),
    );
}

const Reg = u5;

const Regs = struct {
    pub const arg0: Reg = 0;
    pub const arg1: Reg = 1;
    pub const tape_ptr: Reg = 19;
    pub const env_ptr: Reg = 20;
    pub const frame_ptr: Reg = 29;
    pub const link_reg: Reg = 30;
    pub const zero: Reg = 31;
    pub const stack_ptr: Reg = 31;
};

const Cond = enum(u4) {
    equal = 0,
    not_equal = 1,
};

fn add32_immediate(dest: Reg, source: Reg, imm: u12) u32 {
    return (0b0001000100 << 22) | imm12_reg_reg(imm, source, dest);
}

fn add64_immediate(dest: Reg, source: Reg, imm: u12) u32 {
    return (0b1001000100 << 22) | imm12_reg_reg(imm, source, dest);
}

fn sub64_immediate(dest: Reg, source: Reg, imm: u12) u32 {
    return (0b1101000100 << 22) | imm12_reg_reg(imm, source, dest);
}

fn and32_flags(dest: Reg, source1: Reg, source2: Reg) u32 {
    return (0b01101010_000 << 21) | reg_imm6_reg_reg(source2, 0, source1, dest);
}

fn or64(dest: Reg, source1: Reg, source2: Reg) u32 {
    return (0b10101010_000 << 21) | reg_imm6_reg_reg(source2, 0, source1, dest);
}

fn load_reg32_byte(dest: Reg, base: Reg) u32 {
    return (0b00111000011_11111_111_010 << 10) | reg_reg(base, dest);
}

fn load_unscaled_reg64(dest: Reg, base: Reg) u32 {
    return (0b1111100001 << 22) | imm12_reg_reg(0, base, dest);
}

fn load_pair64(dest1: Reg, dest2: Reg, base: Reg, offset: i32) u32 {
    const offset7: i7 = @intCast(@divExact(offset, 8));
    return (0b1010100011 << 22) | imm7_reg_reg_reg(@bitCast(offset7), dest2, base, dest1);
}

fn store_reg32_byte(source: Reg, base: Reg) u32 {
    return (0b00111000001_11111_111_010 << 10) | reg_reg(base, source);
}

fn store_pair64_pre_index(dest1: Reg, dest2: Reg, base: Reg, offset: i32) u32 {
    const offset7: i7 = @intCast(@divExact(offset, 8));
    return (0b1010100110 << 22) | imm7_reg_reg_reg(@bitCast(offset7), dest2, base, dest1);
}

fn branch(cond: Cond, offset: i32) u32 {
    const uoffset: u19 = @bitCast(@as(i19, @intCast(@divExact(offset, 4))));
    return (0b01010100 << 24) | (@as(u32, uoffset) << 5) | @intFromEnum(cond);
}

fn branch_link_reg(reg: Reg) u32 {
    return (0b1101011000_111111000000 << 10) | reg_reg(reg, 0);
}

fn ret(reg: Reg) u32 {
    return (0b1101011001_011111000000 << 10) | reg_reg(reg, 0);
}

fn reg_reg(r1: Reg, r2: Reg) u32 {
    return (@as(u32, r1) << 5) | @as(u32, r2);
}

fn imm12_reg_reg(imm: u12, r1: Reg, r2: Reg) u32 {
    return (@as(u32, imm) << 10) | (@as(u32, r1) << 5) | @as(u32, r2);
}

fn imm7_reg_reg_reg(imm: u7, r1: Reg, r2: Reg, r3: Reg) u32 {
    return (@as(u32, imm) << 15) | (@as(u32, r1) << 10) | (@as(u32, r2) << 5) | @as(u32, r3);
}

fn reg_imm6_reg_reg(r1: Reg, imm: u6, r2: Reg, r3: Reg) u32 {
    return (@as(u32, r1) << 16) | (@as(u32, imm) << 10) | (@as(u32, r2) << 5) | @as(u32, r3);
}
