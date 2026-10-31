/* =============================================================================
 * timer.h  –  Dual-Channel Countdown Timer Driver Header
 * Base: 0x2006_0000
 * =============================================================================
 */

#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>

#define TIMER_BASE          0x20060000U

#define TIMER_REG(off)      (*(volatile uint32_t *)(TIMER_BASE + (off)))

/* Channel A registers */
#define TIMER_CTRL_A        TIMER_REG(0x00U)
#define TIMER_LOAD_A        TIMER_REG(0x04U)
#define TIMER_COUNTER_A     TIMER_REG(0x08U)
#define TIMER_IRQ_EN_A      TIMER_REG(0x0CU)
#define TIMER_IRQ_STAT_A    TIMER_REG(0x10U)

/* Channel B registers */
#define TIMER_CTRL_B        TIMER_REG(0x20U)
#define TIMER_LOAD_B        TIMER_REG(0x24U)
#define TIMER_COUNTER_B     TIMER_REG(0x28U)
#define TIMER_IRQ_EN_B      TIMER_REG(0x2CU)
#define TIMER_IRQ_STAT_B    TIMER_REG(0x30U)

/* Control register bits */
#define TIMER_CTRL_EN           (1U << 0)
#define TIMER_CTRL_AUTO_RELOAD  (1U << 1)
#define TIMER_CTRL_ONE_SHOT     (1U << 2)

/* IRQ bits */
#define TIMER_IRQ_MATCH_IE      (1U << 0)
#define TIMER_IRQ_MATCH         (1U << 0)

static inline void timer_a_start(uint32_t load_val, uint8_t auto_reload) {
    TIMER_LOAD_A = load_val;
    TIMER_CTRL_A = TIMER_CTRL_EN | (auto_reload ? TIMER_CTRL_AUTO_RELOAD : TIMER_CTRL_ONE_SHOT);
}

static inline void timer_b_start(uint32_t load_val, uint8_t auto_reload) {
    TIMER_LOAD_B = load_val;
    TIMER_CTRL_B = TIMER_CTRL_EN | (auto_reload ? TIMER_CTRL_AUTO_RELOAD : TIMER_CTRL_ONE_SHOT);
}

#endif /* TIMER_H */
