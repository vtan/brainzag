const std = @import("std");
const bf = @import("bf.zig");

pub const Interpreter = struct {
    const Self = @This();

    const TAPE_SIZE: usize = 65_536;

    tape: [TAPE_SIZE]u8,
    tape_index: isize,
    op_index: isize,

    pub fn init() Self {
        return Self{
            .tape = std.mem.zeroes([TAPE_SIZE]u8),
            .tape_index = TAPE_SIZE / 2,
            .op_index = 0,
        };
    }

    pub fn run(self: *Self, ops: []const bf.Op) !void {
        while (self.op_index >= 0 and self.op_index < ops.len) {
            try self.step(ops[@intCast(self.op_index)]);
            self.op_index += 1;
        }
    }

    fn step(self: *Self, op: bf.Op) !void {
        switch (op) {
            .add => |amount| self.tape[@intCast(self.tape_index)] +%= @intCast(amount & 0xFF),

            .move => |amount| self.tape_index += @intCast(amount),

            .jump_if_zero => |pair_index| if (self.tape[@intCast(self.tape_index)] == 0) {
                self.op_index = pair_index;
            } else {},

            .jump_back_if_non_zero => |pair_index| if (self.tape[@intCast(self.tape_index)] != 0) {
                self.op_index = pair_index;
            } else {},

            .print => try std.io.getStdOut().writeAll(
                &[1]u8{self.tape[@intCast(self.tape_index)]},
            ),
        }
    }
};
