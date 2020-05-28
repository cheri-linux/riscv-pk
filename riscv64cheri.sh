#!/bin/sh

export CC=riscv64cheri-linux-musl-clang

../configure --host=riscv64-linux-gnu --with-mem-start=0x80000000 --enable-logo --without-payload --enable-print-device-tree

