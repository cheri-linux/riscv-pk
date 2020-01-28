// See LICENSE for license details.

#include "mtrap.h"
#include "bits.h"
#include "config.h"

  .data
  .align 6
trap_table:
#define BAD_TRAP_VECTOR 0
  .dc.a bad_trap
  .dc.a pmp_trap
  .dc.a illegal_insn_trap
  .dc.a bad_trap
  .dc.a misaligned_load_trap
  .dc.a pmp_trap
  .dc.a misaligned_store_trap
  .dc.a pmp_trap
  .dc.a bad_trap
  .dc.a mcall_trap
  .dc.a bad_trap
#ifdef BBL_BOOT_MACHINE
  .dc.a mcall_trap
#else
  .dc.a bad_trap
#endif /* BBL_BOOT_MACHINE */
  .dc.a bad_trap
#define TRAP_FROM_MACHINE_MODE_VECTOR 13
  .dc.a __trap_from_machine_mode
  .dc.a bad_trap
  .dc.a bad_trap

  .option norvc
  .section .text.init,"ax",@progbits
  .globl reset_vector
reset_vector:
  j do_reset

trap_vector:
#if __has_feature(capabilities)
  csrrw csp, mscratchc, csp
#else
  csrrw sp, mscratch, sp
#endif
  beqz sp, .Ltrap_from_machine_mode

#if __has_feature(capabilities)
  sc ca0, 10*REGBYTES(csp)
  sc ca1, 11*REGBYTES(csp)
#else
  STORE a0, 10*REGBYTES(sp)
  STORE a1, 11*REGBYTES(sp)
#endif

  csrr a1, mcause
  bgez a1, .Lhandle_trap_in_machine_mode

  # This is an interrupt.  Discard the mcause MSB and decode the rest.
  sll a1, a1, 1

  # Is it a machine timer interrupt?
  li a0, IRQ_M_TIMER * 2
  bne a0, a1, 1f

  # Yes.  Simply clear MTIE and raise STIP.
  li a0, MIP_MTIP
  csrc mie, a0
  li a0, MIP_STIP
  csrs mip, a0

.Lmret:
  # Go back whence we came.
#if __has_feature(capabilities)
  lc ca0, 10*REGBYTES(csp)
  lc ca1, 11*REGBYTES(csp)
  csrrw csp, mscratchc, csp
#else
  LOAD a0, 10*REGBYTES(csp)
  LOAD a1, 11*REGBYTES(csp)
  csrrw sp, mscratch, sp
#endif
  mret

1:
  # Is it an IPI?
  li a0, IRQ_M_SOFT * 2
  bne a0, a1, .Lbad_trap

  # Yes.  First, clear the MIPI bit.
  LOAD a0, MENTRY_IPI_OFFSET(sp)
  sw x0, (a0)
  fence

  # Now, decode the cause(s).
#ifdef __riscv_atomic
  addi a0, sp, MENTRY_IPI_PENDING_OFFSET
  amoswap.w a0, x0, (a0)
#else
  lw a0, MENTRY_IPI_PENDING_OFFSET(sp)
  sw x0, MENTRY_IPI_PENDING_OFFSET(sp)
#endif
  and a1, a0, IPI_SOFT
  beqz a1, 1f
  csrs mip, MIP_SSIP
1:
  andi a1, a0, IPI_FENCE_I
  beqz a1, 1f
  fence.i
1:
  andi a1, a0, IPI_SFENCE_VMA
  beqz a1, 1f
  sfence.vma
1:
  andi a1, a0, IPI_HALT
  beqz a1, 1f
  wfi
  j 1b
1:
  j .Lmret


.Lhandle_trap_in_machine_mode:
  # Preserve the registers.  Compute the address of the trap handler.
#if __has_feature(capabilities)
  sc cra, 1*REGBYTES(csp)
  sc cgp, 3*REGBYTES(csp)
  sc ctp, 4*REGBYTES(csp)
  sc ct0, 5*REGBYTES(csp)
1:auipcc ct0, %pcrel_hi(trap_table)  # ct0 <- %hi(trap_table)
  sc ct1, 6*REGBYTES(csp)
  sll t1, a1, LOG_REGBYTES         # t1 <- mcause * ptr size
  sc ct2, 7*REGBYTES(csp)
  cincoffset ct0, ct0, t1          # ct0 <- %hi(trap_table)[mcause]
  sc cs0, 8*REGBYTES(csp)
  lc ct1, %pcrel_lo(1b)(ct0)     # ct1 <- trap_table[mcause]
  sc cs1, 9*REGBYTES(csp)
  mv ca0, csp                      # ca0 <- regs
  sc ca2,12*REGBYTES(csp)
  cspecialr ca2, mepcc             # ca2 <- mepcc
  sc ca3,13*REGBYTES(csp)
  cspecialrw ct0, mscratchc, c0    # t0 <- user sp
  sc ca4,14*REGBYTES(csp)
  sc ca5,15*REGBYTES(csp)
  sc ca6,16*REGBYTES(csp)
  sc ca7,17*REGBYTES(csp)
  sc cs2,18*REGBYTES(csp)
  sc cs3,19*REGBYTES(csp)
  sc cs4,20*REGBYTES(csp)
  sc cs5,21*REGBYTES(csp)
  sc cs6,22*REGBYTES(csp)
  sc cs7,23*REGBYTES(csp)
  sc cs8,24*REGBYTES(csp)
  sc cs9,25*REGBYTES(csp)
  sc cs10,26*REGBYTES(csp)
  sc cs11,27*REGBYTES(csp)
  sc ct3,28*REGBYTES(csp)
  sc ct4,29*REGBYTES(csp)
  sc ct5,30*REGBYTES(csp)
  sc ct6,31*REGBYTES(csp)
  sc ct0, 2*REGBYTES(csp)         # sp
  cspecialr ct0, ddc
  sc ct0,33*REGBYTES(csp)
  cspecialr ct0, mtdc
  cspecialw ddc, ct0

#ifndef __riscv_flen
  lw tp, (csp) # Move the emulated FCSR from x0's save slot into tp.
#endif
  STORE x0, (csp) # Zero x0's save slot.

  # Invoke the handler.
  cjalr ct1

#ifndef __riscv_flen
  sw tp, (csp) # Move the emulated FCSR from tp into x0's save slot.
#endif
#else
  STORE ra, 1*REGBYTES(sp)
  STORE gp, 3*REGBYTES(sp)
  STORE tp, 4*REGBYTES(sp)
  STORE t0, 5*REGBYTES(sp)
1:auipc t0, %pcrel_hi(trap_table)  # t0 <- %hi(trap_table)
  STORE t1, 6*REGBYTES(sp)
  sll t1, a1, LOG_REGBYTES         # t1 <- mcause * ptr size
  STORE t2, 7*REGBYTES(sp)
  add t1, t0, t1                   # t1 <- %hi(trap_table)[mcause]
  STORE s0, 8*REGBYTES(sp)
  LOAD t1, %pcrel_lo(1b)(t1)       # t1 <- trap_table[mcause]
  STORE s1, 9*REGBYTES(sp)
  mv a0, sp                        # a0 <- regs
  STORE a2,12*REGBYTES(sp)
  csrr a2, mepc                    # a2 <- mepc
  STORE a3,13*REGBYTES(sp)
  csrrw t0, mscratch, x0           # t0 <- user sp
  STORE a4,14*REGBYTES(sp)
  STORE a5,15*REGBYTES(sp)
  STORE a6,16*REGBYTES(sp)
  STORE a7,17*REGBYTES(sp)
  STORE s2,18*REGBYTES(sp)
  STORE s3,19*REGBYTES(sp)
  STORE s4,20*REGBYTES(sp)
  STORE s5,21*REGBYTES(sp)
  STORE s6,22*REGBYTES(sp)
  STORE s7,23*REGBYTES(sp)
  STORE s8,24*REGBYTES(sp)
  STORE s9,25*REGBYTES(sp)
  STORE s10,26*REGBYTES(sp)
  STORE s11,27*REGBYTES(sp)
  STORE t3,28*REGBYTES(sp)
  STORE t4,29*REGBYTES(sp)
  STORE t5,30*REGBYTES(sp)
  STORE t6,31*REGBYTES(sp)
  STORE t0, 2*REGBYTES(sp)         # sp

#ifndef __riscv_flen
  lw tp, (sp) # Move the emulated FCSR from x0's save slot into tp.
#endif
  STORE x0, (sp) # Zero x0's save slot.

  # Invoke the handler.
  jalr t1

#ifndef __riscv_flen
  sw tp, (sp) # Move the emulated FCSR from tp into x0's save slot.
#endif
#endif

restore_mscratch:
  # Restore mscratch, so future traps will know they didn't come from M-mode.
#if __has_feature(capabilities)
  csrw mscratchc, csp
#else
  csrw mscratch, sp
#endif

restore_regs:
  # Restore all of the registers.
#if __has_feature(capabilities)
  lc ct0,33*REGBYTES(csp)
  cspecialw ddc, ct0
  lc cra, 1*REGBYTES(csp)
  lc cgp, 3*REGBYTES(csp)
  lc ctp, 4*REGBYTES(csp)
  lc ct0, 5*REGBYTES(csp)
  lc ct1, 6*REGBYTES(csp)
  lc ct2, 7*REGBYTES(csp)
  lc cs0, 8*REGBYTES(csp)
  lc cs1, 9*REGBYTES(csp)
  lc ca0,10*REGBYTES(csp)
  lc ca1,11*REGBYTES(csp)
  lc ca2,12*REGBYTES(csp)
  lc ca3,13*REGBYTES(csp)
  lc ca4,14*REGBYTES(csp)
  lc ca5,15*REGBYTES(csp)
  lc ca6,16*REGBYTES(csp)
  lc ca7,17*REGBYTES(csp)
  lc cs2,18*REGBYTES(csp)
  lc cs3,19*REGBYTES(csp)
  lc cs4,20*REGBYTES(csp)
  lc cs5,21*REGBYTES(csp)
  lc cs6,22*REGBYTES(csp)
  lc cs7,23*REGBYTES(csp)
  lc cs8,24*REGBYTES(csp)
  lc cs9,25*REGBYTES(csp)
  lc cs10,26*REGBYTES(csp)
  lc cs11,27*REGBYTES(csp)
  lc ct3,28*REGBYTES(csp)
  lc ct4,29*REGBYTES(csp)
  lc ct5,30*REGBYTES(csp)
  lc ct6,31*REGBYTES(csp)
  lc csp, 2*REGBYTES(csp)
#else
  LOAD ra, 1*REGBYTES(sp)
  LOAD gp, 3*REGBYTES(sp)
  LOAD tp, 4*REGBYTES(sp)
  LOAD t0, 5*REGBYTES(sp)
  LOAD t1, 6*REGBYTES(sp)
  LOAD t2, 7*REGBYTES(sp)
  LOAD s0, 8*REGBYTES(sp)
  LOAD s1, 9*REGBYTES(sp)
  LOAD a0,10*REGBYTES(sp)
  LOAD a1,11*REGBYTES(sp)
  LOAD a2,12*REGBYTES(sp)
  LOAD a3,13*REGBYTES(sp)
  LOAD a4,14*REGBYTES(sp)
  LOAD a5,15*REGBYTES(sp)
  LOAD a6,16*REGBYTES(sp)
  LOAD a7,17*REGBYTES(sp)
  LOAD s2,18*REGBYTES(sp)
  LOAD s3,19*REGBYTES(sp)
  LOAD s4,20*REGBYTES(sp)
  LOAD s5,21*REGBYTES(sp)
  LOAD s6,22*REGBYTES(sp)
  LOAD s7,23*REGBYTES(sp)
  LOAD s8,24*REGBYTES(sp)
  LOAD s9,25*REGBYTES(sp)
  LOAD s10,26*REGBYTES(sp)
  LOAD s11,27*REGBYTES(sp)
  LOAD t3,28*REGBYTES(sp)
  LOAD t4,29*REGBYTES(sp)
  LOAD t5,30*REGBYTES(sp)
  LOAD t6,31*REGBYTES(sp)
  LOAD sp, 2*REGBYTES(sp)
#endif
  mret

.Ltrap_from_machine_mode:
#if __has_feature(capabilities)
  csrr csp, mscratchc
  cincoffset csp, csp, -INTEGER_CONTEXT_SIZE
  sc ca0,10*REGBYTES(csp)
  sc ca1,11*REGBYTES(csp)
#else
  csrr sp, mscratch
  addi sp, sp, -INTEGER_CONTEXT_SIZE
  STORE a0,10*REGBYTES(sp)
  STORE a1,11*REGBYTES(sp)
#endif
  li a1, TRAP_FROM_MACHINE_MODE_VECTOR
  j .Lhandle_trap_in_machine_mode

.Lbad_trap:
  li a1, BAD_TRAP_VECTOR
  j .Lhandle_trap_in_machine_mode

  .globl __redirect_trap
__redirect_trap:
  # reset sp to top of M-mode stack
#if __has_feature(capabilities)
  csetoffset csp, csp, MACHINE_STACK_SIZE - MENTRY_FRAME_SIZE
#else
  li t0, MACHINE_STACK_SIZE
  add sp, sp, t0
  neg t0, t0
  and sp, sp, t0
  addi sp, sp, -MENTRY_FRAME_SIZE
#endif
  j restore_mscratch

__trap_from_machine_mode:
  jal trap_from_machine_mode
  j restore_regs

do_reset:
  li x1, 0
  li x2, 0
  li x3, 0
  li x4, 0
  li x5, 0
  li x6, 0
  li x7, 0
  li x8, 0
  li x9, 0
// save a0 and a1; arguments from previous boot loader stage:
//  li x10, 0
//  li x11, 0
  li x12, 0
  li x13, 0
  li x14, 0
  li x15, 0
  li x16, 0
  li x17, 0
  li x18, 0
  li x19, 0
  li x20, 0
  li x21, 0
  li x22, 0
  li x23, 0
  li x24, 0
  li x25, 0
  li x26, 0
  li x27, 0
  li x28, 0
  li x29, 0
  li x30, 0
  li x31, 0
#if __has_feature(capabilities)
  csrw mscratchc, c0

  cspecialr ct0, ddc
  cspecialw mtdc, ct0

  # write mtcc and make sure it sticks
  la t0, trap_vector
  cspecialr ct1, pcc
  csetaddr ct1, ct1, t0
  cspecialw mtcc, ct1
  cspecialr ct0, mtvec
1:bne t0, t1, 1b

  la sp, stacks
  csrr a3, mhartid
  slli a2, a3, RISCV_PGSHIFT
  add sp, sp, a2
  cfromptr csp, ddc, sp
  csetbounds csp, csp, RISCV_PGSIZE

  csetoffset csp, csp, RISCV_PGSIZE - MENTRY_FRAME_SIZE
#else
  csrw mscratch, x0

  # write mtvec and make sure it sticks
  la t0, trap_vector
  csrw mtvec, t0
  csrr t1, mtvec
1:bne t0, t1, 1b

  la sp, stacks + RISCV_PGSIZE - MENTRY_FRAME_SIZE

  csrr a3, mhartid
  slli a2, a3, RISCV_PGSHIFT
  add sp, sp, a2
#endif

  # Boot on the first hart
  bnez a3, 2f

#if __has_feature(capabilities)
  la t1, init_cap_globals
  cspecialr ct0, pcc
  csetoffset ct0, ct0, t1
  li t1, 1
  csetflags ct0, ct0, t1
  cjalr cra, ct0
#endif
  j init_first_hart

  # set MSIE bit to receive IPI
2:li a2, MIP_MSIP
  csrw mie, a2

.LmultiHart:
#if MAX_HARTS > 1
  # wait for an IPI to signal that it's safe to boot
  wfi

  # masked harts never start
  la a4, disabled_hart_mask
  LOAD a4, 0(a4)
  srl a4, a4, a3
  andi a4, a4, 1
  bnez a4, .LmultiHart

  # only start if mip is set
  csrr a2, mip
  andi a2, a2, MIP_MSIP
  beqz a2, .LmultiHart

  # make sure our hart id is within a valid range
  fence
  li a2, MAX_HARTS
  bgeu a3, a2, 1f
  j init_other_hart
1:
#endif
  wfi
  j .LmultiHart

  .bss
  .align RISCV_PGSHIFT
stacks:
  .skip RISCV_PGSIZE * MAX_HARTS
