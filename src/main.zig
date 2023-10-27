const std = @import("std");

pub fn main() !void {
    const code = try std.io.getStdIn().readToEndAlloc(std.heap.page_allocator, 1024 * 1024 * 1024);

    var ops = try parse(code);
    try fillJumpLocations(&ops);

    var interpreter = Interpreter.init();
    try interpreter.run(try ops.toOwnedSlice());
}

const Op = union(enum) {
    inc: void,
    dec: void,
    left: void,
    right: void,
    jumpIfZero: u32,
    jumpBackIfNonZero: u32,
    print: void,
};

fn parse(code: []const u8) !std.ArrayList(Op) {
    var ops = std.ArrayList(Op).init(std.heap.page_allocator);
    for (code) |char| {
        const op_opt: ?Op = switch (char) {
            '+' => Op.inc,
            '-' => Op.dec,
            '<' => Op.left,
            '>' => Op.right,
            '[' => Op{ .jumpIfZero = 0xDEADBEEF },
            ']' => Op{ .jumpBackIfNonZero = 0xDEADBEEF },
            '.' => Op.print,
            else => null,
        };
        if (op_opt) |op| {
            try ops.append(op);
        }
    }
    return ops;
}

fn fillJumpLocations(ops: *std.ArrayList(Op)) !void {
    var jump_stack = std.ArrayList(u32).init(std.heap.page_allocator);
    for (ops.items, 0..) |*op, i| {
        switch (op.*) {
            .jumpIfZero => {
                try jump_stack.append(@intCast(i));
            },
            .jumpBackIfNonZero => {
                const pair_index = jump_stack.pop();
                ops.items[pair_index].jumpIfZero = @intCast(i);
                op.*.jumpBackIfNonZero = pair_index;
            },
            else => {},
        }
    }
    // TODO: check if jump_stack is empty
}

const Interpreter = struct {
    const TAPE_SIZE: usize = 4096;

    tape: [TAPE_SIZE]u8,
    tape_index: usize,
    op_index: usize,

    pub fn init() Interpreter {
        return Interpreter{
            .tape = undefined,
            .tape_index = TAPE_SIZE / 2,
            .op_index = 0,
        };
    }

    pub fn run(self: *Interpreter, ops: []const Op) !void {
        while (self.op_index < ops.len) {
            try self.step(ops[self.op_index]);
            self.op_index += 1;
        }
    }

    fn step(self: *Interpreter, op: Op) !void {
        switch (op) {
            .inc => self.tape[self.tape_index] +%= 1,
            .dec => self.tape[self.tape_index] -%= 1,
            .left => self.tape_index -= 1,
            .right => self.tape_index += 1,
            .jumpIfZero => |pair_index| if (self.tape[self.tape_index] == 0) {
                self.op_index = pair_index;
            } else {},
            .jumpBackIfNonZero => |pair_index| if (self.tape[self.tape_index] != 0) {
                self.op_index = pair_index;
            } else {},
            .print => try std.io.getStdOut().writeAll(&[1]u8{self.tape[self.tape_index]}),
        }
    }
};
