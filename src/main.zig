const std = @import("std");

const Interpreter = @import("interpreter.zig").Interpreter;
const bf = @import("bf.zig");
const codegen_x86_64 = @import("codegen_x86_64.zig");
const jit = @import("jit.zig");

pub fn main() !void {
    const code = try std.io.getStdIn().readToEndAlloc(std.heap.page_allocator, 1024 * 1024 * 1024);

    var ops = try parse(code);
    compressAddsMoves(&ops);
    try fillJumpLocations(&ops);

    //var interpreter = Interpreter.init();
    //try interpreter.run(try ops.toOwnedSlice());

    var builder = jit.Builder.init();
    try codegen_x86_64.gen(ops.items, &builder);
    const jit_code = try builder.build();

    jit_code.run(&bf.global_tape);
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
