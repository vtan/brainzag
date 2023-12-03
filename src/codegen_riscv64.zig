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
                try builder.emit32s(&[_]u32{
                    // lbu t0, 0(s0)
                    load(Load.u8, Regs.scratch, Regs.tape_ptr, 0),
                    // addi t0, t0, amount
                    addi(Regs.scratch, Regs.scratch, @as(i8, @bitCast(amount))),
                    // sb t0, 0(s0)
                    store(Store.i8, Regs.scratch, Regs.tape_ptr, 0),
                });
            },

            .move => |amount| {
                try builder.emit32s(&[_]u32{
                    // addi s0, s0, amount
                    addi(Regs.tape_ptr, Regs.tape_ptr, @intCast(amount)),
                });
            },

            .jump_if_zero => {
                try builder.emit32(
                    // lbu t0, 0(s0)
                    load(Load.u8, Regs.scratch, Regs.tape_ptr, 0),
                );
                try jump_offsets.append(@intCast(builder.len()));
                // to be filled in by the matching jump back
                try builder.emit32(0);
            },

            .jump_back_if_non_zero => {
                const pair_offset = jump_offsets.pop();

                try builder.emit32(
                    // lbu t0, 0(s0)
                    load(Load.u8, Regs.scratch, Regs.tape_ptr, 0),
                );

                const relative_offset: i13 =
                    @intCast((pair_offset + 4) - (@as(i32, @intCast(builder.len()))));
                try builder.emit32(
                    // bne t0, zero, offset
                    branch(Cond.not_equal, Regs.scratch, Regs.zero, relative_offset),
                );

                const relative_offset_back: i13 =
                    @intCast(@as(i32, @intCast(builder.len())) - pair_offset);
                builder.fill32(
                    // fill the matching jump:
                    // beq t0, zero, offset
                    @intCast(pair_offset),
                    branch(Cond.equal, Regs.scratch, Regs.zero, relative_offset_back),
                );
            },

            .write => {
                try builder.emit32s(&[_]u32{
                    // lbu a0, 0(s0)
                    load(Load.u8, Regs.arg0, Regs.tape_ptr, 0),
                    // ld t0, 0(s1)
                    load(Load.i64, Regs.scratch, Regs.env_ptr, 0),
                    // jalr ra, t0, 0
                    jalr(Regs.return_addr, Regs.scratch, 0),
                });
            },

            .read => {
                try builder.emit32s(&[_]u32{
                    // ld t0, 8(s1)
                    load(Load.i64, Regs.scratch, Regs.env_ptr, 8),
                    // jalr ra, t0, 0
                    jalr(Regs.return_addr, Regs.scratch, 0),
                    // sb a0, 0(s0)
                    store(Store.i8, Regs.arg0, Regs.tape_ptr, 0),
                });
            },
        }
    }

    try genEpilogue(builder);
}

pub fn genPrologue(builder: *jit.Builder) !void {
    try builder.emit32s(&[_]u32{
        // addi sp, sp, -24
        addi(Regs.stack_ptr, Regs.stack_ptr, -24),
        // sd s0, 0(sp)
        store(Store.i64, Regs.tape_ptr, Regs.stack_ptr, 0),
        // sd s1, 8(sp)
        store(Store.i64, Regs.env_ptr, Regs.stack_ptr, 8),
        // sd ra, 16(sp)
        store(Store.i64, Regs.return_addr, Regs.stack_ptr, 16),

        // addi s0, a0, 0
        addi(Regs.tape_ptr, Regs.arg0, 0),
        // addi s1, a1, 0
        addi(Regs.env_ptr, Regs.arg1, 0),
    });
}

pub fn genEpilogue(builder: *jit.Builder) !void {
    try builder.emit32s(&[_]u32{
        // ld s0, 0(sp)
        load(Load.i64, Regs.tape_ptr, Regs.stack_ptr, 0),
        // ld s1, 8(sp)
        load(Load.i64, Regs.env_ptr, Regs.stack_ptr, 8),
        // ld ra, 16(sp)
        load(Load.i64, Regs.return_addr, Regs.stack_ptr, 16),
        // addi sp, sp, 24
        addi(Regs.stack_ptr, Regs.stack_ptr, 24),

        // jalr zero, ra, 0
        jalr(Regs.zero, Regs.return_addr, 0),
    });
}

const Reg = u5;

const Regs = struct {
    pub const zero: Reg = 0;
    pub const return_addr: Reg = 1;
    pub const stack_ptr: Reg = 2;
    pub const scratch: Reg = 5;
    pub const tape_ptr: Reg = 8;
    pub const env_ptr: Reg = 9;
    pub const arg0: Reg = 10;
    pub const arg1: Reg = 11;
};

fn jalr(dest: Reg, src: Reg, offset: i12) u32 {
    return encode_i(0b1100111, 0, dest, src, @bitCast(offset));
}

const Load = enum(u3) {
    u8 = 0b100,
    i64 = 0b011,
};

fn load(width: Load, dest: Reg, src: Reg, offset: i12) u32 {
    return encode_i(0b0000011, @intFromEnum(width), dest, src, @bitCast(offset));
}

const Store = enum(u3) {
    i8 = 0b000,
    i64 = 0b011,
};

fn store(width: Store, src: Reg, base: Reg, offset: i12) u32 {
    return encode_s(0b0100011, @intFromEnum(width), base, src, @bitCast(offset));
}

fn addi(dest: Reg, src: Reg, imm: i12) u32 {
    return encode_i(0b0010011, 0, dest, src, @bitCast(imm));
}

const Cond = enum(u3) {
    equal = 0b000,
    not_equal = 0b001,
};

fn branch(cond: Cond, reg1: Reg, reg2: Reg, offset: i13) u32 {
    const offset12: i12 = @intCast(@divExact(offset, 2));
    const imm: u12 = @bitCast(offset12);
    return 0b1100011 |
        (@as(u32, (imm >> 10) & 1) << 7) |
        (@as(u32, imm & 0b1111) << 8) |
        (@as(u32, @intFromEnum(cond)) << 12) |
        (@as(u32, reg1) << 15) |
        (@as(u32, reg2) << 20) |
        (@as(u32, (imm >> 4) & 0b111111) << 25) |
        (@as(u32, imm >> 11) << 31);
}

fn encode_i(opcode: u7, funct3: u3, rd: Reg, rs1: Reg, imm: u12) u32 {
    return @as(u32, opcode) |
        (@as(u32, rd) << 7) |
        (@as(u32, funct3) << 12) |
        (@as(u32, rs1) << 15) |
        (@as(u32, imm) << 20);
}

fn encode_s(opcode: u7, funct3: u3, rs1: Reg, rs2: Reg, imm: u12) u32 {
    return @as(u32, opcode) |
        (@as(u32, imm & 0b11111) << 7) |
        (@as(u32, funct3) << 12) |
        (@as(u32, rs1) << 15) |
        (@as(u32, rs2) << 20) |
        (@as(u32, imm >> 5) << 25);
}
