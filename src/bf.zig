pub const Op = union(enum) {
    add: i32,
    move: i32,
    jump_if_zero: u32,
    jump_back_if_non_zero: u32,
    print: void,
};
