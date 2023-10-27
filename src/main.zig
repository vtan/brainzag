const std = @import("std");

const bf = @import("bf.zig");
const Interpreter = @import("interpreter.zig").Interpreter;

pub fn main() !void {
    const code = try std.io.getStdIn().readToEndAlloc(std.heap.page_allocator, 1024 * 1024 * 1024);

    var ops = try parse(code);
    std.debug.print("{}\n", .{ops.items.len});
    compressAddsMoves(&ops);
    std.debug.print("{}\n", .{ops.items.len});
    try fillJumpLocations(&ops);

    var interpreter = Interpreter.init();
    try interpreter.run(try ops.toOwnedSlice());
}

fn parse(code: []const u8) !std.ArrayList(bf.Op) {
    var ops = std.ArrayList(bf.Op).init(std.heap.page_allocator);
    for (code) |char| {
        const op_opt: ?bf.Op = switch (char) {
            '+' => bf.Op{ .add = 1 },
            '-' => bf.Op{ .add = -1 },
            '<' => bf.Op{ .move = -1 },
            '>' => bf.Op{ .move = 1 },
            '[' => bf.Op{ .jump_if_zero = 0xDEADBEEF },
            ']' => bf.Op{ .jump_back_if_non_zero = 0xDEADBEEF },
            '.' => bf.Op.print,
            else => null,
        };
        if (op_opt) |op| {
            try ops.append(op);
        }
    }
    return ops;
}

fn fillJumpLocations(ops: *std.ArrayList(bf.Op)) !void {
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

fn compressAddsMoves(ops: *std.ArrayList(bf.Op)) void {
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
