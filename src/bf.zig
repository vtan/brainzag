pub const Op = union(enum) {
    inc: void,
    dec: void,
    left: void,
    right: void,
    jump_if_zero: u32,
    jump_back_if_non_zero: u32,
    print: void,
};
