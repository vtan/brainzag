const std = @import("std");

pub const Op = union(enum) {
    add: i8,
    move: i32,
    jump_if_zero: u32,
    jump_back_if_non_zero: u32,
    print: void,
};

pub const TAPE_SIZE = 4 * 1024 * 1024;
pub const Tape = [TAPE_SIZE]u8;

pub var global_tape: Tape = [_]u8{0} ** TAPE_SIZE;

pub fn parse(code: []const u8) !std.ArrayList(Op) {
    var ops = std.ArrayList(Op).init(std.heap.page_allocator);
    for (code) |char| {
        const op_opt: ?Op = switch (char) {
            '+' => Op{ .add = 1 },
            '-' => Op{ .add = -1 },
            '<' => Op{ .move = -1 },
            '>' => Op{ .move = 1 },
            '[' => Op{ .jump_if_zero = 0xDEADBEEF },
            ']' => Op{ .jump_back_if_non_zero = 0xDEADBEEF },
            '.' => Op.print,
            else => null,
        };
        if (op_opt) |op| {
            try ops.append(op);
        }
    }
    return ops;
}

pub fn fillJumpLocations(ops: *std.ArrayList(Op)) !void {
    var jump_stack = std.ArrayList(u32).init(std.heap.page_allocator);
    for (ops.items, 0..) |*op, i| {
        switch (op.*) {
            .jump_if_zero => {
                try jump_stack.append(@intCast(i));
            },
            .jump_back_if_non_zero => {
                const pair_index = jump_stack.pop();
                ops.items[pair_index].jump_if_zero = @intCast(i);
                op.*.jump_back_if_non_zero = pair_index;
            },
            else => {},
        }
    }
    // TODO: check if jump_stack is empty
}

pub fn compressAddsMoves(ops: *std.ArrayList(Op)) void {
    var i: usize = 1;
    while (i < ops.items.len) {
        const curr = ops.items[i];
        var prev = &ops.items[i - 1];
        switch (curr) {
            .add => |a| {
                switch (prev.*) {
                    .add => |*b| {
                        b.* += a;
                        _ = ops.orderedRemove(i);
                        continue;
                    },
                    else => {},
                }
            },

            .move => |a| {
                switch (prev.*) {
                    .move => |*b| {
                        b.* += a;
                        _ = ops.orderedRemove(i);
                        continue;
                    },
                    else => {},
                }
            },

            else => {},
        }
        i += 1;
    }
}
