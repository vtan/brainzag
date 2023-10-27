const std = @import("std");
const bf = @import("bf.zig");

pub const Interpreter = struct {
    const Self = @This();

    const TAPE_SIZE: usize = 4096;

    tape: [TAPE_SIZE]u8,
    tape_index: usize,
    op_index: usize,

    pub fn init() Self {
        return Self{
            .tape = undefined,
            .tape_index = TAPE_SIZE / 2,
            .op_index = 0,
        };
    }

    pub fn run(self: *Self, ops: []const bf.Op) !void {
        while (self.op_index < ops.len) {
            try self.step(ops[self.op_index]);
            self.op_index += 1;
        }
    }

    fn step(self: *Self, op: bf.Op) !void {
        switch (op) {
            .inc => self.tape[self.tape_index] +%= 1,
            .dec => self.tape[self.tape_index] -%= 1,
            .left => self.tape_index -= 1,
            .right => self.tape_index += 1,
            .jump_if_zero => |pair_index| if (self.tape[self.tape_index] == 0) {
                self.op_index = pair_index;
            } else {},
            .jump_back_if_non_zero => |pair_index| if (self.tape[self.tape_index] != 0) {
                self.op_index = pair_index;
            } else {},
            .print => try std.io.getStdOut().writeAll(&[1]u8{self.tape[self.tape_index]}),
        }
    }
};
