// See LICENSE for license details.

#include "mtrap.h"
#include "bits.h"
#include "config.h"

#if __has_feature(capabilities)
#define PTR .chericap
#else
#define PTR .dc.a
#endif

  .data
  .align 6
trap_table:
#define BAD_TRAP_VECTOR 0
  PTR bad_trap
  PTR pmp_trap
  PTR illegal_insn_trap
  PTR bad_trap
  PTR misaligned_load_trap
  PTR pmp_trap
  PTR misaligned_store_trap
  PTR pmp_trap
  PTR bad_trap
  PTR mcall_trap
  PTR bad_trap
#ifdef BBL_BOOT_MACHINE
  PTR mcall_trap
#else
  PTR bad_trap
#endif /* BBL_BOOT_MACHINE */
  PTR bad_trap
#define TRAP_FROM_MACHINE_MODE_VECTOR 13
  PTR __trap_from_machine_mode
  PTR bad_trap
  PTR bad_trap

  PTR bad_trap
  PTR bad_trap
  PTR bad_trap
  PTR bad_trap
  PTR bad_trap
  PTR bad_trap
  PTR bad_trap
  PTR bad_trap
  PTR bad_trap
  PTR bad_trap
  PTR bad_trap
  PTR bad_trap
  PTR bad_trap /* 0x1c CHERI excception */
  PTR bad_trap
  PTR bad_trap
  PTR bad_trap

  .option norvc
  .section .text.init,"ax",@progbits
  .globl reset_vector
#if __has_feature(capabilities)
  .option nocapmode
#endif
reset_vector:
  j do_reset
#if __has_feature(capabilities)
  .option capmode
#endif

trap_vector:
#if __has_feature(capabilities)
  cspecialrw csp, mscratchc, csp
#else
  csrrw sp, mscratch, sp
#endif
  beqz sp, .Ltrap_from_machine_mode

#if __has_feature(capabilities)
  csc ca0, 10*REGBYTES(csp)
  csc ca1, 11*REGBYTES(csp)
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
  clc ca0, 10*REGBYTES(csp)
  clc ca1, 11*REGBYTES(csp)
  cspecialrw csp, mscratchc, csp
#else
  LOAD a0, 10*REGBYTES(sp)
  LOAD a1, 11*REGBYTES(sp)
  csrrw sp, mscratch, sp
#endif
  mret

1:
  # Is it an IPI?
  li a0, IRQ_M_SOFT * 2
  bne a0, a1, .Lbad_trap

  # Yes.  First, clear the MIPI bit.
#if __has_feature(capabilities)
  clc ca0, MENTRY_IPI_OFFSET(csp)
  csw x0, (ca0)
#else
  LOAD a0, MENTRY_IPI_OFFSET(sp)
  sw x0, (a0)
#endif
  fence

  # Now, decode the cause(s).
#if __has_feature(capabilities)
  cincoffset ca0, csp, MENTRY_IPI_PENDING_OFFSET
  camoswap.w a0, x0, (ca0)
#else
#ifdef __riscv_atomic
  addi a0, sp, MENTRY_IPI_PENDING_OFFSET
  amoswap.w a0, x0, (a0)
#else
  lw a0, MENTRY_IPI_PENDING_OFFSET(sp)
  sw x0, MENTRY_IPI_PENDING_OFFSET(sp)
#endif
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
  csc cra, 1*REGBYTES(csp)
  csc cgp, 3*REGBYTES(csp)
  csc ctp, 4*REGBYTES(csp)
  csc ct0, 5*REGBYTES(csp)
1:auipcc ct0, %pcrel_hi(trap_table)  # ct0 <- %hi(trap_table)
  csc ct1, 6*REGBYTES(csp)
  sll t1, a1, LOG_REGBYTES         # t1 <- mcause * ptr size
  csc ct2, 7*REGBYTES(csp)
  cincoffset ct0, ct0, t1          # ct0 <- %hi(trap_table)[mcause]
  csc cs0, 8*REGBYTES(csp)
  clc ct1, %pcrel_lo(1b)(ct0)      # ct1 <- trap_table[mcause]
  csc cs1, 9*REGBYTES(csp)
  cmove ca0, csp                   # ca0 <- regs
  csc ca2,12*REGBYTES(csp)
  cspecialr ca2, mepcc             # ca2 <- mepcc
  csc ca3,13*REGBYTES(csp)
  cmove ct0, c0                    # c0 input for cspecialrw means cspecialr
  cspecialrw ct0, mscratchc, ct0   # t0 <- user sp
  csc ca4,14*REGBYTES(csp)
  csc ca5,15*REGBYTES(csp)
  csc ca6,16*REGBYTES(csp)
  csc ca7,17*REGBYTES(csp)
  csc cs2,18*REGBYTES(csp)
  csc cs3,19*REGBYTES(csp)
  csc cs4,20*REGBYTES(csp)
  csc cs5,21*REGBYTES(csp)
  csc cs6,22*REGBYTES(csp)
  csc cs7,23*REGBYTES(csp)
  csc cs8,24*REGBYTES(csp)
  csc cs9,25*REGBYTES(csp)
  csc cs10,26*REGBYTES(csp)
  csc cs11,27*REGBYTES(csp)
  csc ct3,28*REGBYTES(csp)
  csc ct4,29*REGBYTES(csp)
  csc ct5,30*REGBYTES(csp)
  csc ct6,31*REGBYTES(csp)
  csc ct0, 2*REGBYTES(csp)         # sp
  cspecialr ct0, ddc
  csc ct0,32*REGBYTES(csp)
  cspecialr ct0, mtdc
  cspecialw ddc, ct0

#ifndef __riscv_flen
  clw tp, (csp) # Move the emulated FCSR from x0's save slot into tp.
#endif
  csd x0, (csp) # Zero x0's save slot.

  # Invoke the handler.
  cjalr cra, ct1

#ifndef __riscv_flen
  csw tp, (csp) # Move the emulated FCSR from tp into x0's save slot.
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
  cspecialw mscratchc, csp
#else
  csrw mscratch, sp
#endif

restore_regs:
  # Restore all of the registers.
#if __has_feature(capabilities)
  clc ct0,32*REGBYTES(csp)
  cspecialw ddc, ct0
  clc cra, 1*REGBYTES(csp)
  clc cgp, 3*REGBYTES(csp)
  clc ctp, 4*REGBYTES(csp)
  clc ct0, 5*REGBYTES(csp)
  clc ct1, 6*REGBYTES(csp)
  clc ct2, 7*REGBYTES(csp)
  clc cs0, 8*REGBYTES(csp)
  clc cs1, 9*REGBYTES(csp)
  clc ca0,10*REGBYTES(csp)
  clc ca1,11*REGBYTES(csp)
  clc ca2,12*REGBYTES(csp)
  clc ca3,13*REGBYTES(csp)
  clc ca4,14*REGBYTES(csp)
  clc ca5,15*REGBYTES(csp)
  clc ca6,16*REGBYTES(csp)
  clc ca7,17*REGBYTES(csp)
  clc cs2,18*REGBYTES(csp)
  clc cs3,19*REGBYTES(csp)
  clc cs4,20*REGBYTES(csp)
  clc cs5,21*REGBYTES(csp)
  clc cs6,22*REGBYTES(csp)
  clc cs7,23*REGBYTES(csp)
  clc cs8,24*REGBYTES(csp)
  clc cs9,25*REGBYTES(csp)
  clc cs10,26*REGBYTES(csp)
  clc cs11,27*REGBYTES(csp)
  clc ct3,28*REGBYTES(csp)
  clc ct4,29*REGBYTES(csp)
  clc ct5,30*REGBYTES(csp)
  clc ct6,31*REGBYTES(csp)
  clc csp, 2*REGBYTES(csp)
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
  cspecialr csp, mscratchc
  cincoffset csp, csp, -INTEGER_CONTEXT_SIZE
  csc ca0,10*REGBYTES(csp)
  csc ca1,11*REGBYTES(csp)
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
  .type __redirect_trap, @function
__redirect_trap:
  # reset sp to top of M-mode stack
#if __has_feature(capabilities)
  li t0, MACHINE_STACK_SIZE - MENTRY_FRAME_SIZE
  csetoffset csp, csp, t0
#else
  li t0, MACHINE_STACK_SIZE
  add sp, sp, t0
  neg t0, t0
  and sp, sp, t0
  addi sp, sp, -MENTRY_FRAME_SIZE
#endif
  j restore_mscratch
.size __redirect_trap, . - __redirect_trap

  .type __trap_from_machine_mode, @function
__trap_from_machine_mode:
  jal trap_from_machine_mode
  j restore_regs
.size __trap_from_machine_mode, . - __trap_from_machine_mode

#if __has_feature(capabilities)
  .globl enter_supervisor_mode
  .type enter_supervisor_mode, @function
enter_supervisor_mode:
  # Reset mstatus
  csrr t0, mstatus
  li t1, ~(MSTATUS_MPP | MSTATUS_MPIE)
  and t0, t0, t1
  li t1, PRV_S << 11
  or t0, t0, t1
  csrw mstatus, t0

  # Reset mscratchc
  li t0, MACHINE_STACK_SIZE - MENTRY_FRAME_SIZE
  csetoffset csp, csp, t0
  cspecialw mscratchc, csp

#ifndef __riscv_flen
  csd x0, (csp) # Zero x0's save slot.
#endif

  # Rederive full-permissions mepcc
  cspecialr ct0, ddc
  csetoffset ca0, ct0, a0
  csetflags ca0, ca0, x0
  cspecialw mepcc, ca0

  # Set arguments and return
  cmove ca0, ca1
  cmove ca1, ca2
  mret
  .size enter_supervisor_mode, . - enter_supervisor_mode
#endif

#if __has_feature(capabilities)
  .option nocapmode
#endif
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
  # c0 input for cspecialrw means cspecialr
  cmove ct0, c0
  cspecialw mscratchc, ct0

  cspecialr ct0, ddc
  cspecialw mtdc, ct0

  # switch into cap-mode
  lla t0, 1f
  cspecialr ct1, pcc
  csetoffset ct0, ct1, t0
  li t1, 1
  csetflags ct0, ct0, t1
  cjr ct0
1:
  .option capmode

  # write mtcc and make sure it sticks
  cllc ct0, trap_vector
  cspecialw mtcc, ct0
  cspecialr ct1, mtcc
1:bne t0, t1, 1b

  cllc csp, stacks

  csrr a3, mhartid
  slli a2, a3, RISCV_PGSHIFT
  cincoffset csp, csp, a2
  li t0, RISCV_PGSIZE
  csetbounds csp, csp, t0
  add t0, t0, -MENTRY_FRAME_SIZE
  csetoffset csp, csp, t0

  # Zero out BSS
  cllc ct0, _fbss
  cllc ct1, _end
  beq t0, t1, 2f
1:csc c0, 0(ct0)
  cincoffset ct0, ct0, REGBYTES
  bne t0, t1, 1b
2:
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

  # Zero out BSS
  lla t0, _fbss
  lla t1, _end
  beq t0, t1, 2f
1:STORE zero, 0(t0)
  addi t0, t0, REGBYTES
  bne t0, t1, 1b
2:
#endif

  # Boot on the first hart
  bnez a3, 2f

#if __has_feature(capabilities)
  # Save a0/a1 with hartid/DTB from previous boot loader stage
  mv s0, a0
  mv s1, a1

  # Initialise captable
  cllc ct0, init_cap_globals
  cjalr cra, ct0

  # Restore hartid/DTB for init_first_hart, and turn DTB into a capability
  mv a0, s0
  cspecialr ct0, ddc
  csetoffset ca1, ct0, s1
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
#if __has_feature(capabilities)
1:auipcc ca4, %pcrel_hi(disabled_hart_mask)
  cincoffset ca4, ca4, %pcrel_lo(1b)
  cld a4, 0(ca4)
#else
  la a4, disabled_hart_mask
  LOAD a4, 0(a4)
#endif
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
