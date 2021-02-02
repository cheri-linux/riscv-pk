// See LICENSE for license details.

#include "mtrap.h"
#include "atomic.h"
#include "vm.h"
#include "fp_emulation.h"
#include "fdt.h"
#include "uart.h"
#include "uart16550.h"
#include "finisher.h"
#include "disabled_hart_mask.h"
#include "htif.h"
#include "string.h"
#if __has_feature(capabilities)
#include <cheri_init_globals.h>
#endif

#if __has_feature(capabilities)
extern void init_cap_globals(void);

void init_cap_globals(void)
{
  cheri_init_globals_3(__builtin_cheri_global_data_get(),
    __builtin_cheri_program_counter_get(),
    __builtin_cheri_global_data_get());
}
#endif

pte_t* root_page_table;
uintptr_t mem_size;
volatile uint64_t* mtime;
volatile uint32_t* plic_priorities;
size_t plic_ndevs;
void* kernel_start;
void* kernel_end;

static void mstatus_init()
{
  unsigned long mstatus = 0;

  // Enable FPU
  if (supports_extension('F'))
    mstatus |= MSTATUS_FS;

  // Enable vector extension
  if (supports_extension('V'))
    mstatus |= MSTATUS_VS;

  write_csr(mstatus, mstatus);

  // Enable user/supervisor use of perf counters
  if (supports_extension('S'))
    write_csr(scounteren, -1);
  if (supports_extension('U'))
    write_csr(mcounteren, -1);

  // Enable software interrupts
  write_csr(mie, MIP_MSIP);

  // Disable paging
  if (supports_extension('S'))
    write_csr(satp, 0);
}

// send S-mode interrupts and most exceptions straight to S-mode
static void delegate_traps()
{
  if (!supports_extension('S'))
    return;

  unsigned long interrupts = MIP_SSIP | MIP_STIP | MIP_SEIP;
  unsigned long exceptions =
    (1U << CAUSE_MISALIGNED_FETCH) |
    (1U << CAUSE_FETCH_PAGE_FAULT) |
    (1U << CAUSE_BREAKPOINT) |
    (1U << CAUSE_LOAD_PAGE_FAULT) |
    (1U << CAUSE_STORE_PAGE_FAULT) |
    (1U << CAUSE_USER_ECALL);
#if __has_feature(capabilities)
  exceptions |= 1U << 0x1a; /* LOAD_CAP_PAGE_FAULT */
  exceptions |= 1U << 0x1b; /* STORE_CAP_PAGE_FAULT */
  exceptions |= 1U << 0x1c; /* CHERI exception */
#endif

  write_csr(mideleg, interrupts);
  write_csr(medeleg, exceptions);
  assert(read_csr(mideleg) == interrupts);
  assert(read_csr(medeleg) == exceptions);
}

static void fp_init()
{
  if (!supports_extension('F'))
    return;

  assert(read_csr(mstatus) & MSTATUS_FS);

#ifdef __riscv_flen
  for (int i = 0; i < 32; i++)
    init_fp_reg(i);
  write_csr(fcsr, 0);

# if __riscv_flen == 32
  size_t d_mask = 1 << ('D' - 'A');
  clear_csr(misa, d_mask);
  assert(!(read_csr(misa) & d_mask));
# endif

#else
  size_t fd_mask = (1 << ('F' - 'A')) | (1 << ('D' - 'A'));
  clear_csr(misa, fd_mask);
  assert(!(read_csr(misa) & fd_mask));
#endif
}

hls_t* hls_init(uintptr_t id)
{
  hls_t* hls = OTHER_HLS(id);
  memset(hls, 0, sizeof(*hls));
  return hls;
}

static void memory_init()
{
  mem_size = mem_size / MEGAPAGE_SIZE * MEGAPAGE_SIZE;
}

static void hpm_init()
{

// TODO have those defined in a separate header? Where should that live?
#define EVENT_REDIRECT                0x1
#define EVENT_BRANCH                  0x3
#define EVENT_JAL                     0x4
#define EVENT_JALR                    0x5
#define EVENT_TRAP                    0x2

#define EVENT_LOAD_WAIT              0x10
#define EVENT_CAP_LOAD_TAG_SET       0x1c
#define EVENT_CAP_STORE_TAG_SET      0x1d

#define EVENT_ITLB_MISS_WAIT         0x2b
#define EVENT_ICACHE_LOAD            0x20
#define EVENT_ICACHE_LOAD_MISS       0x21
#define EVENT_ICACHE_LOAD_MISS_WAIT  0x22

#define EVENT_DTLB_ACCESS            0x39
#define EVENT_DTLB_MISS              0x3a
#define EVENT_DTLB_MISS_WAIT         0x3b
#define EVENT_DCACHE_LOAD            0x30
#define EVENT_DCACHE_LOAD_MISS       0x31
#define EVENT_DCACHE_LOAD_MISS_WAIT  0x32
#define EVENT_DCACHE_STORE           0x33
#define EVENT_DCACHE_STORE_MISS      0x34

#define EVENT_LLCACHE_LOAD_MISS      0x00 // TODO
#define EVENT_LLCACHE_LOAD_MISS_WAIT 0x00 // TODO

#define EVENT_TAGCACHE_LOAD          0x4e
#define EVENT_TAGCACHE_LOAD_MISS     0x4f
#define EVENT_TAGCACHE_STORE         0x4c
#define EVENT_TAGCACHE_STORE_MISS    0x4d
#define EVENT_TAGCACHE_EVICT         0x50

// TODO have those derived from a config file? What's an appropriate mechanism?
#define EVENT_3  EVENT_REDIRECT
#define EVENT_4  EVENT_BRANCH
#define EVENT_5  EVENT_JAL
#define EVENT_6  EVENT_JALR
#define EVENT_7  EVENT_TRAP
#define EVENT_8  EVENT_LOAD_WAIT
#define EVENT_9  EVENT_CAP_LOAD_TAG_SET
#define EVENT_10 EVENT_CAP_STORE_TAG_SET
#define EVENT_11 EVENT_ITLB_MISS_WAIT
#define EVENT_12 EVENT_ICACHE_LOAD
#define EVENT_13 EVENT_ICACHE_LOAD_MISS
#define EVENT_14 EVENT_ICACHE_LOAD_MISS_WAIT
#define EVENT_15 EVENT_DTLB_ACCESS
#define EVENT_16 EVENT_DTLB_MISS
#define EVENT_17 EVENT_DTLB_MISS_WAIT
#define EVENT_18 EVENT_DCACHE_LOAD
#define EVENT_19 EVENT_DCACHE_LOAD_MISS
#define EVENT_20 EVENT_DCACHE_LOAD_MISS_WAIT
#define EVENT_21 EVENT_DCACHE_STORE
#define EVENT_22 EVENT_DCACHE_STORE_MISS
#define EVENT_23 EVENT_LLCACHE_LOAD_MISS
#define EVENT_24 EVENT_LLCACHE_LOAD_MISS_WAIT
#define EVENT_25 EVENT_TAGCACHE_LOAD
#define EVENT_26 EVENT_TAGCACHE_LOAD_MISS
#define EVENT_27 EVENT_TAGCACHE_STORE
#define EVENT_28 EVENT_TAGCACHE_STORE_MISS
#define EVENT_29 EVENT_TAGCACHE_EVICT

  asm volatile (// handle trap on implementations not supporting HPM CSRs
#if __has_feature(capabilities)
                "cllc ct1, 1f\n\t"
                "cspecialrw ct1, mtcc, ct1\n\t"
#else
                "la t1, 1f\n\t"
                "csrrw t1, mtvec, t1\n\t"
#endif
                // inhibit all counters
                "li t0, 0xfffffff8\n\t"
                "csrs mcountinhibit, t0\n\t"
                // install all events
                "li t0, " STR(EVENT_3) "\n\t"
                "csrw mhpmevent3, t0\n\t"
                "li t0, " STR(EVENT_4) "\n\t"
                "csrw mhpmevent4, t0\n\t"
                "li t0, " STR(EVENT_5) "\n\t"
                "csrw mhpmevent5, t0\n\t"
                "li t0, " STR(EVENT_6) "\n\t"
                "csrw mhpmevent6, t0\n\t"
                "li t0, " STR(EVENT_7) "\n\t"
                "csrw mhpmevent7, t0\n\t"
                "li t0, " STR(EVENT_8) "\n\t"
                "csrw mhpmevent8, t0\n\t"
                "li t0, " STR(EVENT_9) "\n\t"
                "csrw mhpmevent9, t0\n\t"
                "li t0, " STR(EVENT_10) "\n\t"
                "csrw mhpmevent10, t0\n\t"
                "li t0, " STR(EVENT_11) "\n\t"
                "csrw mhpmevent11, t0\n\t"
                "li t0, " STR(EVENT_12) "\n\t"
                "csrw mhpmevent12, t0\n\t"
                "li t0, " STR(EVENT_13) "\n\t"
                "csrw mhpmevent13, t0\n\t"
                "li t0, " STR(EVENT_14) "\n\t"
                "csrw mhpmevent14, t0\n\t"
                "li t0, " STR(EVENT_15) "\n\t"
                "csrw mhpmevent15, t0\n\t"
                "li t0, " STR(EVENT_16) "\n\t"
                "csrw mhpmevent16, t0\n\t"
                "li t0, " STR(EVENT_17) "\n\t"
                "csrw mhpmevent17, t0\n\t"
                "li t0, " STR(EVENT_18) "\n\t"
                "csrw mhpmevent18, t0\n\t"
                "li t0, " STR(EVENT_19) "\n\t"
                "csrw mhpmevent19, t0\n\t"
                "li t0, " STR(EVENT_20) "\n\t"
                "csrw mhpmevent20, t0\n\t"
                "li t0, " STR(EVENT_21) "\n\t"
                "csrw mhpmevent21, t0\n\t"
                "li t0, " STR(EVENT_22) "\n\t"
                "csrw mhpmevent22, t0\n\t"
                "li t0, " STR(EVENT_23) "\n\t"
                "csrw mhpmevent23, t0\n\t"
                "li t0, " STR(EVENT_24) "\n\t"
                "csrw mhpmevent24, t0\n\t"
                "li t0, " STR(EVENT_25) "\n\t"
                "csrw mhpmevent25, t0\n\t"
                "li t0, " STR(EVENT_26) "\n\t"
                "csrw mhpmevent26, t0\n\t"
                "li t0, " STR(EVENT_27) "\n\t"
                "csrw mhpmevent27, t0\n\t"
                "li t0, " STR(EVENT_28) "\n\t"
                "csrw mhpmevent28, t0\n\t"
                "li t0, " STR(EVENT_29) "\n\t"
                "csrw mhpmevent29, t0\n\t"
                // initialize all counters to 0
                "li t0, 0\n\t"
                "csrw mhpmcounter3, t0\n\t"
                "csrw mhpmcounter4, t0\n\t"
                "csrw mhpmcounter5, t0\n\t"
                "csrw mhpmcounter6, t0\n\t"
                "csrw mhpmcounter7, t0\n\t"
                "csrw mhpmcounter8, t0\n\t"
                "csrw mhpmcounter9, t0\n\t"
                "csrw mhpmcounter10, t0\n\t"
                "csrw mhpmcounter11, t0\n\t"
                "csrw mhpmcounter12, t0\n\t"
                "csrw mhpmcounter13, t0\n\t"
                "csrw mhpmcounter14, t0\n\t"
                "csrw mhpmcounter15, t0\n\t"
                "csrw mhpmcounter16, t0\n\t"
                "csrw mhpmcounter17, t0\n\t"
                "csrw mhpmcounter18, t0\n\t"
                "csrw mhpmcounter19, t0\n\t"
                "csrw mhpmcounter20, t0\n\t"
                "csrw mhpmcounter21, t0\n\t"
                "csrw mhpmcounter22, t0\n\t"
                "csrw mhpmcounter23, t0\n\t"
                "csrw mhpmcounter24, t0\n\t"
                "csrw mhpmcounter25, t0\n\t"
                "csrw mhpmcounter26, t0\n\t"
                "csrw mhpmcounter27, t0\n\t"
                "csrw mhpmcounter28, t0\n\t"
                "csrw mhpmcounter29, t0\n\t"
                // bitmask in t0
                "li t0, 0xfffffff8\n\t"
                // enable user access -- questionable practice here...
                "csrs mcounteren, t0\n\t"
                // un-inhibit all counters
                "csrc mcountinhibit, t0\n\t"
                // restore exception vector
                ".align 2\n"
                "1:\n\t"
#if __has_feature(capabilities)
                "cspecialw mtcc, ct1"
#else
                "csrw mtvec, t1"
#endif
                : // no outputs
                : // no inputs
                : "t0",
#if __has_feature(capabilities)
                  "ct1"
#else
                  "t1"
#endif
                );
}

static void hart_init()
{
  mstatus_init();
  fp_init();
  hpm_init();
#ifndef BBL_BOOT_MACHINE
  delegate_traps();
#endif /* BBL_BOOT_MACHINE */
  setup_pmp();
}

static void plic_init()
{
  for (size_t i = 1; i <= plic_ndevs; i++)
    plic_priorities[i] = 1;
}

static void prci_test()
{
  assert(!(read_csr(mip) & MIP_MSIP));
  *HLS()->ipi = 1;
  assert(read_csr(mip) & MIP_MSIP);
  *HLS()->ipi = 0;

  assert(!(read_csr(mip) & MIP_MTIP));
  *HLS()->timecmp = 0;
  assert(read_csr(mip) & MIP_MTIP);
  *HLS()->timecmp = -1ULL;
}

static void hart_plic_init()
{
  // clear pending interrupts
  *HLS()->ipi = 0;
  *HLS()->timecmp = -1ULL;
  write_csr(mip, 0);

  if (!plic_ndevs)
    return;

  size_t ie_words = (plic_ndevs + 8 * sizeof(*HLS()->plic_s_ie) - 1) /
		(8 * sizeof(*HLS()->plic_s_ie));
  for (size_t i = 0; i < ie_words; i++) {
     if (HLS()->plic_s_ie) {
        // Supervisor not always present
        HLS()->plic_s_ie[i] = __UINT32_MAX__;
     }
  }
  *HLS()->plic_m_thresh = 1;
  if (HLS()->plic_s_thresh) {
      // Supervisor not always present
      *HLS()->plic_s_thresh = 0;
  }
}

static void wake_harts()
{
  for (int hart = 0; hart < MAX_HARTS; ++hart)
    if ((((~disabled_hart_mask & hart_mask) >> hart) & 1))
      *OTHER_HLS(hart)->ipi = 1; // wakeup the hart
}

void init_first_hart(uintptr_t hartid, uintptr_t dtb)
{
  // Confirm console as early as possible
  query_uart(dtb);
  query_uart16550(dtb);
  query_htif(dtb);
  printm("bbl loader\r\n");

  hart_init();
  hls_init(0); // this might get called again from parse_config_string

  // Find the power button early as well so die() works
  query_finisher(dtb);

  query_mem(dtb);
  query_harts(dtb);
  query_clint(dtb);
  query_plic(dtb);
  query_chosen(dtb);

  wake_harts();

  plic_init();
  hart_plic_init();
  //prci_test();
  memory_init();
  boot_loader(dtb);
}

void init_other_hart(uintptr_t hartid, uintptr_t dtb)
{
  hart_init();
  hart_plic_init();
  boot_other_hart(dtb);
}

void setup_pmp(void)
{
  // Set up a PMP to permit access to all of memory.
  // Ignore the illegal-instruction trap if PMPs aren't supported.
  unsigned long pmpc = PMP_NAPOT | PMP_R | PMP_W | PMP_X;
#if __has_feature(capabilities)
  asm volatile ("cllc ct0, 1f\n\t"
                "cspecialrw ct0, mtcc, ct0\n\t"
                "csrw pmpaddr0, %1\n\t"
                "csrw pmpcfg0, %0\n\t"
                ".align 2\n\t"
                "1: cspecialw mtcc, ct0"
                : : "r" (pmpc), "r" (-1UL) : "ct0");
#else
  asm volatile ("la t0, 1f\n\t"
                "csrrw t0, mtvec, t0\n\t"
                "csrw pmpaddr0, %1\n\t"
                "csrw pmpcfg0, %0\n\t"
                ".align 2\n\t"
                "1: csrw mtvec, t0"
                : : "r" (pmpc), "r" (-1UL) : "t0");
#endif
}

#if !__has_feature(capabilities)
void enter_supervisor_mode(void (*fn)(uintptr_t), uintptr_t arg0, uintptr_t arg1)
{
  uintptr_t mstatus = read_csr(mstatus);
  mstatus = INSERT_FIELD(mstatus, MSTATUS_MPP, PRV_S);
  mstatus = INSERT_FIELD(mstatus, MSTATUS_MPIE, 0);
  write_csr(mstatus, mstatus);
  write_csr(mscratch, MACHINE_STACK_TOP() - MENTRY_FRAME_SIZE);
#ifndef __riscv_flen
  uintptr_t *p_fcsr = MACHINE_STACK_TOP() - MENTRY_FRAME_SIZE; // the x0's save slot
  *p_fcsr = 0;
#endif
  write_csr(mepc, fn);

  register uintptr_t a0 asm ("a0") = arg0;
  register uintptr_t a1 asm ("a1") = arg1;
  asm volatile ("mret" : : "r" (a0), "r" (a1));
  __builtin_unreachable();
}
#endif

void enter_machine_mode(void (*fn)(uintptr_t, uintptr_t), uintptr_t arg0, uintptr_t arg1)
{
  unsigned long mstatus = read_csr(mstatus);
  mstatus = INSERT_FIELD(mstatus, MSTATUS_MPIE, 0);
  write_csr(mstatus, mstatus);
#if __has_feature(capabilities)
  write_scr(mscratchc, MACHINE_STACK_TOP() - MENTRY_FRAME_SIZE);
  fn = __builtin_cheri_flags_set(fn, 0);
#else
  write_csr(mscratch, MACHINE_STACK_TOP() - MENTRY_FRAME_SIZE);
#endif

  /* Jump to the payload's entry point */
  fn(arg0, arg1);

  __builtin_unreachable();
}
