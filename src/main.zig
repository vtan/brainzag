const std = @import("std");
const clap = @import("clap");

const Interpreter = @import("interpreter.zig").Interpreter;
const bf = @import("bf.zig");
const codegen_x86_64 = @import("codegen_x86_64.zig");
const jit = @import("jit.zig");

pub fn main() !void {
    const params = try parseParams() orelse return;

    const file = try std.fs.cwd().openFile(params.filename, .{});
    const input = try file.readToEndAlloc(std.heap.page_allocator, 16 * 1024 * 1024);

    var ops = try bf.parse(input);

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
    filename: []const u8,
};

const ParamsError = error{
    MissingFilename,
};

fn parseParams() !?Params {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help       Display this help and exit
        \\-j, --jit        Use JIT compilation instead of the interpreter
        \\-o, --optimize   Enable optimizations
        \\<FILE>
    );
    const parsers = comptime .{
        .FILE = clap.parsers.string,
    };
    var diag = clap.Diagnostic{};
    var stderr = std.io.getStdErr().writer();
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
    }) catch |err| {
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
    } else if (res.positionals.len == 0) {
        try stderr.writeAll("Missing filename\nUsage: ");
        try clap.usage(stderr, clap.Help, &params);
        try stderr.writeAll("\n");
        return ParamsError.MissingFilename;
    } else {
        return Params{
            .jit = res.args.jit != 0,
            .optimize = res.args.optimize != 0,
            .filename = res.positionals[0],
        };
    }
}
