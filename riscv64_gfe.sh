#!/bin/sh

export CC=riscv64-linux-musl-clang

../configure --host=riscv64-linux-gnu --with-mem-start=0xC0000000 --enable-logo --without-payload --enable-print-device-tree --enable-board-gfe

