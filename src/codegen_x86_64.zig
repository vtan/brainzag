const bf = @import("bf.zig");
const jit = @import("jit.zig");

// rbp: tape pointer
// rbx: pointer to external functions
// rdi: function arg 1
// rsi: function arg 2

pub fn gen(ops: []const bf.Op, builder: *jit.Builder) !void {
    _ = ops;
    try genPrologue(builder);

    // call [rsi]
    try builder.emit(&[_]u8{ 0xff, 0x16 });

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
