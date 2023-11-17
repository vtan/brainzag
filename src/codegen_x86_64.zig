const std = @import("std");
const bf = @import("bf.zig");
const jit = @import("jit.zig");

// rbp: tape pointer
// rbx: pointer to external functions
// rdi: function arg 1
// rsi: function arg 2

pub fn gen(ops: []const bf.Op, builder: *jit.Builder) !void {
    try genPrologue(builder);

    var jump_offsets = std.ArrayList(i32).init(std.heap.page_allocator);
    defer jump_offsets.deinit();

    for (ops) |op| {
        switch (op) {
            .add => |amount| {
                // add byte [rbp], $amount
                try builder.emit(&[_]u8{ 0x80, 0x45, 0x00, @bitCast(amount) });
            },

            .move => |amount| {
                // add rbp, byte $amount
                const byte: i8 = @intCast(amount);
                try builder.emit(&[_]u8{ 0x48, 0x83, 0xC5, @bitCast(byte) });
            },

            .jump_if_zero => {
                // mov al, [rbp]
                try builder.emit(&[_]u8{ 0x8a, 0x45, 0x00 });
                // cmp al, 0
                try builder.emit(&[_]u8{ 0x3c, 0x00 });

                try jump_offsets.append(@intCast(builder.len()));

                // jz ...
                try builder.emit(&[_]u8{ 0x0f, 0x84, 0, 0, 0, 0 });
            },

            .jump_back_if_non_zero => {
                const pair_offset = jump_offsets.pop();

                // mov al, [rbp]
                try builder.emit(&[_]u8{ 0x8a, 0x45, 0x00 });
                // cmp al, 0
                try builder.emit(&[_]u8{ 0x3c, 0x00 });
                // jnz pair_offset
                try builder.emit(&[_]u8{ 0x0f, 0x85 });

                const back_offset = (pair_offset + 6) - (@as(i32, @intCast(builder.len())) + 4);
                try builder.emit32(@bitCast(back_offset));

                // fill the offset in the matching jz
                const forward_offset = @as(i32, @intCast(builder.len())) - (pair_offset + 6);
                builder.fill32(
                    @intCast(pair_offset + 2),
                    @bitCast(forward_offset),
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
    // ret
    try builder.emit8(0xc3);
}
