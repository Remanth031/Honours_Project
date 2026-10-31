/* =============================================================================
 * gpio.h  –  AXI4-Lite GPIO Driver Header
 * Base: 0x2004_0000
 * =============================================================================
 */

#ifndef GPIO_H
#define GPIO_H

#include <stdint.h>

#define GPIO_BASE       0x20040000U

#define GPIO_REG(off)   (*(volatile uint32_t *)(GPIO_BASE + (off)))

#define GPIO_DATA_OUT   GPIO_REG(0x00U)
#define GPIO_DATA_IN    GPIO_REG(0x04U)
#define GPIO_DIR        GPIO_REG(0x08U)
#define GPIO_IRQ_EN     GPIO_REG(0x0CU)
#define GPIO_IRQ_STAT   GPIO_REG(0x10U)

static inline void gpio_set_dir(uint32_t mask, uint32_t is_out) {
    if (is_out) {
        GPIO_DIR |= mask;
    } else {
        GPIO_DIR &= ~mask;
    }
}

static inline void gpio_write(uint32_t val) {
    GPIO_DATA_OUT = val;
}

static inline uint32_t gpio_read(void) {
    return GPIO_DATA_IN;
}

#endif /* GPIO_H */
