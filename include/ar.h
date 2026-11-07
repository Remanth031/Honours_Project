/* =============================================================================
 * ar.h  –  Array Rasterizer Accelerator Driver Header
 * Base: 0x2000_0000
 * =============================================================================
 */

#ifndef AR_H
#define AR_H

#include <stdint.h>

#define AR_BASE         0x20000000U

#define AR_REG(off)     (*(volatile uint32_t *)(AR_BASE + (off)))

#define AR_CTRL         AR_REG(0x00U)
#define AR_STATUS       AR_REG(0x04U)
#define AR_PRIM_TYPE    AR_REG(0x08U)
#define AR_PRIM_BASE    AR_REG(0x0CU)
#define AR_PRIM_COUNT   AR_REG(0x10U)
#define AR_COLOR        AR_REG(0x14U)
#define AR_FB_BASE      AR_REG(0x18U)
#define AR_FB_STRIDE    AR_REG(0x1CU)
#define AR_IRQ_EN       AR_REG(0x20U)

/* Control bits */
#define AR_CTRL_START       (1U << 0)
#define AR_CTRL_RESET       (1U << 1)

/* Status bits */
#define AR_STATUS_BUSY      (1U << 0)
#define AR_STATUS_DONE      (1U << 1)
#define AR_STATUS_ERROR     (1U << 2)

/* Primitive types */
#define AR_PRIM_LINE        0U
#define AR_PRIM_TRIANGLE    1U

/* IRQ enable bits */
#define AR_IRQ_DONE_IE      (1U << 0)
#define AR_IRQ_ERR_IE       (1U << 1)

/* Helper: Pack 16-bit X and Y coordinates into 32-bit vertex word */
static inline uint32_t ar_pack_vertex(int16_t x, int16_t y) {
    return (((uint32_t)(uint16_t)y) << 16) | ((uint32_t)(uint16_t)x);
}

#endif /* AR_H */
