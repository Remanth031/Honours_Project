/* =============================================================================
 * spi.h  –  AXI4-Lite SPI Master Driver Header
 * Base: 0x2005_0000
 * =============================================================================
 */

#ifndef SPI_H
#define SPI_H

#include <stdint.h>

#define SPI_BASE        0x20050000U

#define SPI_REG(off)    (*(volatile uint32_t *)(SPI_BASE + (off)))

#define SPI_CTRL        SPI_REG(0x00U)
#define SPI_TX_DATA     SPI_REG(0x04U)
#define SPI_RX_DATA     SPI_REG(0x08U)
#define SPI_STATUS      SPI_REG(0x0CU)
#define SPI_IRQ_EN      SPI_REG(0x10U)
#define SPI_IRQ_STAT    SPI_REG(0x14U)

/* Control register bits */
#define SPI_CTRL_EN         (1U << 0)
#define SPI_CTRL_CPOL       (1U << 1)
#define SPI_CTRL_CPHA       (1U << 2)
#define SPI_CTRL_DIV_MASK   (0x1FU << 3)
#define SPI_CTRL_DIV_SHIFT  3

/* Status register bits */
#define SPI_STAT_BUSY       (1U << 0)
#define SPI_STAT_TX_EMPTY   (1U << 1)
#define SPI_STAT_RX_VALID   (1U << 2)

/* IRQ bits */
#define SPI_IRQ_DONE_IE     (1U << 0)
#define SPI_IRQ_DONE        (1U << 0)

static inline uint8_t spi_transfer_byte(uint8_t tx) {
    while (SPI_STATUS & SPI_STAT_BUSY);
    SPI_TX_DATA = tx;
    while (SPI_STATUS & SPI_STAT_BUSY);
    return (uint8_t)(SPI_RX_DATA & 0xFFU);
}

#endif /* SPI_H */
