/* =============================================================================
 * vga.h  –  VGA Configuration Registers Driver Header
 * Base: 0x2002_0000
 * =============================================================================
 */

#ifndef VGA_H
#define VGA_H

#include <stdint.h>

#define VGA_BASE        0x20020000U

#define VGA_REG(off)    (*(volatile uint32_t *)(VGA_BASE + (off)))

#define VGA_CTRL        VGA_REG(0x00U)
#define VGA_H_PARAMS    VGA_REG(0x04U)
#define VGA_V_PARAMS    VGA_REG(0x08U)
#define VGA_H_SYNC      VGA_REG(0x0CU)
#define VGA_V_SYNC      VGA_REG(0x10U)
#define VGA_FB_BASE     VGA_REG(0x14U)
#define VGA_FB_STRIDE   VGA_REG(0x18U)
#define VGA_STATUS      VGA_REG(0x1CU)

/* Control bits */
#define VGA_CTRL_EN         (1U << 0)
#define VGA_CTRL_VSYNC_POL  (1U << 1)
#define VGA_CTRL_HSYNC_POL  (1U << 2)

/* Status bits */
#define VGA_STAT_VSYNC_ACT  (1U << 0)
#define VGA_STAT_HSYNC_ACT  (1U << 1)

static inline void vga_init(uint32_t fb_base, uint32_t stride) {
    VGA_FB_BASE   = fb_base;
    VGA_FB_STRIDE = stride;
    VGA_CTRL     |= VGA_CTRL_EN;
}

#endif /* VGA_H */
