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
