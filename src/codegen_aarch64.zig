const bf = @import("bf.zig");
const jit = @import("jit.zig");

// x19: tape pointer
// x20: pointer to external functions
// x0: function arg 1
// x1: function arg 2

pub fn gen(ops: []const bf.Op, builder: *jit.Builder) !void {
    _ = ops;
    // stp x29, x30, [sp, -16]!
    try builder.emit(&[_]u8{ 0xFD, 0x7B, 0xBF, 0xA9 });
    // mov x29, sp
    try builder.emit(&[_]u8{ 0xFD, 0x03, 0x00, 0x91 });
    // mov x0, 65
    try builder.emit(&[_]u8{ 0x20, 0x08, 0x80, 0xD2 });
    // ldr x1, [x1]
    try builder.emit(&[_]u8{ 0x21, 0x00, 0x40, 0xF8 });
    // blr x1
    try builder.emit(&[_]u8{ 0x20, 0x00, 0x3F, 0xD6 });
    // ldp x29, x30, [sp], 16
    try builder.emit(&[_]u8{ 0xFD, 0x7B, 0xC1, 0xA8 });
    // ret
    try builder.emit(&[_]u8{ 0xC0, 0x03, 0x5F, 0xD6 });
}
