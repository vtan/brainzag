const std = @import("std");

const bf = @import("bf.zig");
const Interpreter = @import("interpreter.zig").Interpreter;

pub fn main() !void {
    const code = try std.io.getStdIn().readToEndAlloc(std.heap.page_allocator, 1024 * 1024 * 1024);

    var ops = try parse(code);
    try fillJumpLocations(&ops);

    var interpreter = Interpreter.init();
    try interpreter.run(try ops.toOwnedSlice());
}

fn parse(code: []const u8) !std.ArrayList(bf.Op) {
    var ops = std.ArrayList(bf.Op).init(std.heap.page_allocator);
    for (code) |char| {
        const op_opt: ?bf.Op = switch (char) {
            '+' => bf.Op.inc,
            '-' => bf.Op.dec,
            '<' => bf.Op.left,
            '>' => bf.Op.right,
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
