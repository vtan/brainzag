#!/usr/bin/env bash

EXECUTABLE='zig-out/bin/brainzag'
TEST_STDIN='word1 word2 word3'

ARCHS=(x86_64 aarch64 riscv64)
FLAGS=(-o -j -jo)
TESTS=(dollar hello hello2 wc)

ARCH=''

build () {
  echo "Building for $ARCH..."
  zig build "-Dtarget=$ARCH-linux"
  echo "Testing $ARCH..."
}

run () {
  echo -ne "$1 with $2\t\t"
  "qemu-$ARCH-static" "$EXECUTABLE" "$2" "$1" <<<"$TEST_STDIN" | tr -d '\n'
  echo
}

for ARCH in ${ARCHS[@]}; do
  build
  for test in ${TESTS[@]}; do
    for flags in ${FLAGS[@]}; do
      run "test/$test.bf" "$flags"
    done
  done
  echo
done
