const std = @import("std");
const builtin = @import("builtin");
const clap = @import("clap");

const Interpreter = @import("interpreter.zig").Interpreter;
const bf = @import("bf.zig");
const codegen_aarch64 = @import("codegen_aarch64.zig");
const codegen_riscv64 = @import("codegen_riscv64.zig");
const codegen_x86_64 = @import("codegen_x86_64.zig");
const jit = @import("jit.zig");

const MainError = error{
    MissingFilename,
    UnsupportedCpuArch,
};

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

        switch (builtin.cpu.arch) {
            std.Target.Cpu.Arch.x86_64 => try codegen_x86_64.gen(ops.items, &builder),
            std.Target.Cpu.Arch.aarch64 => try codegen_aarch64.gen(ops.items, &builder),
            std.Target.Cpu.Arch.riscv64 => try codegen_riscv64.gen(ops.items, &builder),
            else => return MainError.UnsupportedCpuArch,
        }

        if (params.dump_code) {
            var code_file = try std.fs.cwd().createFile("code", .{});
            try code_file.writeAll(builder.bytes.items);
        }

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
    dump_code: bool,
    filename: []const u8,
};

fn parseParams() !?Params {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help       Display this help and exit
        \\-j, --jit        Use JIT compilation instead of the interpreter
        \\-o, --optimize   Enable optimizations
        \\-d, --dump-code  Write compiled code to the file `code`
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
        return MainError.MissingFilename;
    } else {
        return Params{
            .jit = res.args.jit != 0,
            .optimize = res.args.optimize != 0,
            .dump_code = res.args.@"dump-code" != 0,
            .filename = res.positionals[0],
        };
    }
}
