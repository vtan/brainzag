const std = @import("std");
const clap = @import("clap");

const Interpreter = @import("interpreter.zig").Interpreter;
const bf = @import("bf.zig");
const codegen_x86_64 = @import("codegen_x86_64.zig");
const jit = @import("jit.zig");

pub fn main() !void {
    const params = try parseParams() orelse return;

    const code = try std.io.getStdIn().readToEndAlloc(std.heap.page_allocator, 1024 * 1024 * 1024);

    var ops = try bf.parse(code);

    if (params.optimize) {
        bf.compressAddsMoves(&ops);
    }
    try bf.fillJumpLocations(&ops);

    if (params.jit) {
        var builder = jit.Builder.init();
        try codegen_x86_64.gen(ops.items, &builder);

        const jit_code = try builder.build();
        jit_code.run(&bf.global_tape);
    } else {
        var interpreter = Interpreter.init();
        try interpreter.run(try ops.toOwnedSlice());
    }
}

const Params = struct {
    jit: bool,
    optimize: bool,
};

fn parseParams() !?Params {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help       Display this help and exit
        \\-j, --jit        Use JIT compilation instead of the interpreter
        \\-o, --optimize   Enable optimizations
    );
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        var stderr = std.io.getStdErr().writer();
        diag.report(stderr, err) catch {};
        try stderr.writeAll("Usage: ");
        try clap.usage(stderr, clap.Help, &params);
        try stderr.writeAll("\n");
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        return null;
    } else {
        return Params{
            .jit = res.args.jit != 0,
            .optimize = res.args.optimize != 0,
        };
    }
}
