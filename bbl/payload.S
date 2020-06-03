// See LICENSE for license details.

#include "config.h"
#include "encoding.h"

  .section ".payload","a",@progbits

#if RELAXED_ALIGNMENT
  /* align payload minimally */
  .align 3
#else
  /* align payload to megapage */
  .align RISCV_PGSHIFT + RISCV_PGLEVEL_BITS
#endif

  .globl _payload_start
  .type _payload_start, @object
_payload_start:
  .incbin BBL_PAYLOAD
  .type _payload_end, @object
  .globl _payload_end
_payload_end:
  .size _payload_start, _payload_end - _payload_start
  .size _payload_end, 0
