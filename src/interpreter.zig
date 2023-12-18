const std = @import("std");
const bf = @import("bf.zig");

pub const Interpreter = struct {
    const Self = @This();

    tape: []u8,
    tape_index: isize,
    op_index: isize,

    pub fn init() Self {
        return Self{
            .tape = &bf.global_tape,
            .tape_index = bf.TAPE_SIZE / 2,
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
            .add => |amount| {
                var p = &self.tape[@intCast(self.tape_index)];
                var signed: i8 = @bitCast(p.*);
                signed +%= amount;
                p.* = @bitCast(signed);
            },

            .move => |amount| self.tape_index += @intCast(amount),

            .jump_if_zero => |pair_index| if (self.tape[@intCast(self.tape_index)] == 0) {
                self.op_index = pair_index;
            } else {},

            .jump_back_if_non_zero => |pair_index| if (self.tape[@intCast(self.tape_index)] != 0) {
                self.op_index = pair_index;
            } else {},

            .write => try std.io.getStdOut().writeAll(
                &[1]u8{self.tape[@intCast(self.tape_index)]},
            ),

            .read => {
                var buf: [1]u8 = undefined;
                const read_count = try std.io.getStdIn().read(&buf);
                if (read_count == 0) {
                    self.tape[@intCast(self.tape_index)] = 0;
                } else {
                    self.tape[@intCast(self.tape_index)] = buf[0];
                }
            },
        }
    }
};
