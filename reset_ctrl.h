/* =============================================================================
 * reset_ctrl.h  –  Reset & Watchdog Controller Driver Header
 * Base: 0x2007_0000
 * =============================================================================
 */

#ifndef RESET_CTRL_H
#define RESET_CTRL_H

#include <stdint.h>

#define RESET_CTRL_BASE     0x20070000U

#define RESET_REG(off)      (*(volatile uint32_t *)(RESET_CTRL_BASE + (off)))

#define RESET_CAUSE         RESET_REG(0x00U)
#define RESET_SOFT_RESET    RESET_REG(0x04U)
#define RESET_WDT_CTRL      RESET_REG(0x08U)
#define RESET_WDT_LOAD      RESET_REG(0x0CU)
#define RESET_WDT_KICK      RESET_REG(0x10U)
#define RESET_WDT_STATUS    RESET_REG(0x14U)

/* Reset cause bits */
#define RESET_CAUSE_POR     (1U << 0)
#define RESET_CAUSE_WDT     (1U << 1)
#define RESET_CAUSE_SOFT    (1U << 2)

/* Soft reset trigger key */
#define RESET_SOFT_KEY      0xDEADBEEFU

/* Watchdog control bits */
#define WDT_CTRL_EN         (1U << 0)
#define WDT_STAT_EXPIRED    (1U << 0)

static inline void system_soft_reset(void) {
    RESET_SOFT_RESET = RESET_SOFT_KEY;
}

static inline void watchdog_kick(void) {
    RESET_WDT_KICK = 1U;
}

#endif /* RESET_CTRL_H */
