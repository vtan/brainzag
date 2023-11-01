const std = @import("std");
const bf = @import("bf.zig");
const jit = @import("jit.zig");

// rbp: tape pointer
// rbx: pointer to external functions
// rdi: function arg 1
// rsi: function arg 2

pub fn gen(ops: []const bf.Op, builder: *jit.Builder) !void {
    try genPrologue(builder);

    var forward_jump_offsets = std.AutoHashMap(u32, i32).init(std.heap.page_allocator);
    defer forward_jump_offsets.deinit();

    for (ops, 0..) |op, i| {
        switch (op) {
            .add => |amount| {
                // add byte [rbp], $amount
                try builder.emit(&[_]u8{ 0x80, 0x45, 0x00, @bitCast(amount) });
            },

            .move => |amount| {
                if (amount >= -128 and amount < 127) {
                    // add rbp, byte $amount
                    const byte: i8 = @intCast(amount);
                    try builder.emit(&[_]u8{ 0x48, 0x83, 0xC5, @bitCast(byte) });
                } else {
                    unreachable;
                }
            },

            .jump_if_zero => {
                // mov al, [rbp]
                try builder.emit(&[_]u8{ 0x8a, 0x45, 0x00 });
                // test al, al
                try builder.emit(&[_]u8{ 0x84, 0xc0 });

                try forward_jump_offsets.put(
                    @intCast(i),
                    @intCast(builder.len()),
                );

                // jz ...
                try builder.emit(&[_]u8{ 0x0f, 0x84, 0, 0, 0, 0 });
            },

            .jump_back_if_non_zero => |dest| {
                const pair_offset = forward_jump_offsets.get(dest) orelse unreachable;

                // mov al, [rbp]
                try builder.emit(&[_]u8{ 0x8a, 0x45, 0x00 });
                // test al, al
                try builder.emit(&[_]u8{ 0x84, 0xc0 });
                // jnz pair_offset
                try builder.emit(&[_]u8{ 0x0f, 0x85 });
                try builder.emit32(@bitCast((pair_offset + 6) - (@as(i32, @intCast(builder.len())) + 4)));

                // fill the offset in the matching jz
                builder.fill32(
                    @intCast(pair_offset + 2),
                    @bitCast(@as(i32, @intCast(builder.len())) - (pair_offset + 6)),
                );
            },

            .write => {
                // mov rdi, [rbp]
                try builder.emit(&[_]u8{ 0x48, 0x8b, 0x7d, 0x00 });
                // call [rbx]
                try builder.emit(&[_]u8{ 0xff, 0x13 });
            },

            .read => {
                // call [rbx+8]
                try builder.emit(&[_]u8{ 0xff, 0x53, 0x08 });
                // mov [rbp], al
                try builder.emit(&[_]u8{ 0x88, 0x45, 0x00 });
            },
        }
    }

    try genEpilogue(builder);
}

fn genPrologue(builder: *jit.Builder) !void {
    // push rbp
    try builder.emit8(0x55);
    // push rbx
    try builder.emit8(0x53);
    // mov rbp, rdi
    try builder.emit(&[_]u8{ 0x48, 0x89, 0xfd });
    // mov rbx, rsi
    try builder.emit(&[_]u8{ 0x48, 0x89, 0xf3 });
}

fn genEpilogue(builder: *jit.Builder) !void {
    // pop rbx
    try builder.emit8(0x5b);
    // pop rbp
    try builder.emit8(0x5d);
    // xor rax, rax
    try builder.emit(&[_]u8{ 0x48, 0x31, 0xc0 });
    // ret
    try builder.emit8(0xc3);
}
