# brainzag

An interpreter and JIT compiler for the Brainfuck programming language, written in Zig.
JIT compilation is implemented for the x86-64, ARM64 and 64-bit RISC-V CPU architectures.

```console
$ zig build run -- -o test/hello.bf     # interpret with optimizations
$ zig build run -- -jo test/hello.bf    # compile with optimizations
```
