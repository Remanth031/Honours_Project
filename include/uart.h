/* =============================================================================
 * uart.h  –  AXI-Lite UART IP Driver Header
 *
 * Register map derived directly from the RTL source files:
 *   src/include/axi_uart.vh
 *   src/include/axi_uart_defines.vh
 *   src/rtl/axi_uart_top.v
 *
 * AXI address decoding: addr[4:2] selects the register (word-addressed).
 * ADDR_WIDTH = 5 bits → byte offsets shown below.
 *
 * Register map (base = UART_BASE):
 *   Offset  Name            Access   Description
 *   0x00    RBR  (DLAB=0)   R        Receiver Buffer Register (RX data byte)
 *   0x00    THR  (DLAB=0)   W        Transmitter Holding Register (TX data byte)
 *   0x04    IER  (DLAB=0)   R/W      Interrupt Enable Register  [0]=RX_IRQ_EN
 *   0x08    BAUD (DLAB=1)   R/W      Baud Rate Divisor (32-bit)
 *   0x0C    LCR             R/W      Line Control Register
 *                                      [7]   DLAB  – divisor latch access bit
 *                                      [4]   parity mode (0=odd, 1=even)
 *                                      [3]   parity enable
 *                                      [2]   stop bits (0=1bit, 1=2bits)
 *   0x14    LSR             R        Line Status Register (read-only)
 *                                      [6]   TEMT  – TX shift reg empty
 *                                      [5]   THRE  – TX FIFO has space
 *                                      [0]   DR    – RX data ready
 *
 * Baud rate divisor formula (from RTL):
 *   divisor = MAIN_CLK_HZ / baud_rate
 *   Default: 100 MHz / 115200 ≈ 868  (simulation clock)
 *            50  MHz / 115200 ≈ 434  (FPGA_FULL clock)
 * =============================================================================
 */

#ifndef UART_H
#define UART_H

#include <stdint.h>

/* ---------------------------------------------------------------------------
 * Base address of the AXI-Lite UART IP in the SoC address map.
 * Assign an address that does NOT clash with Data Memory (0x0000_0000),
 * Framebuffer (0x1000_0000), AR Control (0x2000_0000), HPM (0x2001_0000),
 * or VGA regs (0x2002_0000).
 * Place UART at 0x2003_0000 (next free 4 KB page in the peripheral region).
 * --------------------------------------------------------------------------- */
#define UART_BASE   0x20030000U

/* ---------------------------------------------------------------------------
 * Register offsets (byte addresses, word-aligned)
 * --------------------------------------------------------------------------- */
#define UART_RBR_OFF    0x00U   /* RX data byte      (read,  DLAB=0) */
#define UART_THR_OFF    0x00U   /* TX data byte      (write, DLAB=0) */
#define UART_IER_OFF    0x04U   /* Interrupt enable  (R/W,   DLAB=0) */
#define UART_BAUD_OFF   0x08U   /* Baud divisor      (R/W,   DLAB=1) */
#define UART_LCR_OFF    0x0CU   /* Line control      (R/W)           */
#define UART_LSR_OFF    0x14U   /* Line status       (read-only)     */

/* ---------------------------------------------------------------------------
 * Register accessors  (volatile 32-bit, AXI4-Lite is always 32-bit wide)
 * --------------------------------------------------------------------------- */
#define UART_REG(off)   (*(volatile uint32_t *)(UART_BASE + (off)))

#define UART_RBR        UART_REG(UART_RBR_OFF)
#define UART_THR        UART_REG(UART_THR_OFF)
#define UART_IER        UART_REG(UART_IER_OFF)
#define UART_BAUD       UART_REG(UART_BAUD_OFF)
#define UART_LCR        UART_REG(UART_LCR_OFF)
#define UART_LSR        UART_REG(UART_LSR_OFF)

/* ---------------------------------------------------------------------------
 * LCR bit fields  (from axi_uart.vh)
 * --------------------------------------------------------------------------- */
#define LCR_DLAB            (1U << 7)   /* Divisor Latch Access Bit */
#define LCR_PARITY_MODE     (1U << 4)   /* 0=odd, 1=even            */
#define LCR_PARITY_EN       (1U << 3)   /* 1=enable parity          */
#define LCR_STOP_BITS       (1U << 2)   /* 0=1 stop bit, 1=2 stop   */

/* ---------------------------------------------------------------------------
 * IER bit fields
 * --------------------------------------------------------------------------- */
#define IER_RX_IRQ_EN       (1U << 0)   /* Enable RX data-ready IRQ */

/* ---------------------------------------------------------------------------
 * LSR bit fields  (from axi_uart.vh)
 * --------------------------------------------------------------------------- */
#define LSR_TEMT            (1U << 6)   /* TX shift register empty  */
#define LSR_THRE            (1U << 5)   /* TX FIFO has free space   */
#define LSR_DR              (1U << 0)   /* RX data ready            */

/* ---------------------------------------------------------------------------
 * Baud rate divisor constants
 *   Formula: divisor = CLK_HZ / baud
 * --------------------------------------------------------------------------- */
#define UART_CLK_HZ         100000000UL /* default sim clock: 100 MHz */
#define UART_BAUD_115200    (UART_CLK_HZ / 115200UL)   /* ≈ 868 */
#define UART_BAUD_9600      (UART_CLK_HZ / 9600UL)     /* ≈ 10417 */

/* ===========================================================================
 * Driver API
 * =========================================================================== */

/**
 * uart_init() – configure UART: 8N1, no parity, 1 stop bit, set baud divisor.
 * @divisor: baud-rate divisor value (use UART_BAUD_xxx macros)
 */
static inline void uart_init(uint32_t divisor)
{
    /* 1. Set DLAB=1 to access baud-rate divisor */
    UART_LCR = LCR_DLAB;

    /* 2. Write the divisor */
    UART_BAUD = divisor;

    /* 3. Clear DLAB → 8-bit word, no parity, 1 stop bit */
    UART_LCR = 0x00U;
}

/**
 * uart_tx_ready() – returns non-zero if TX FIFO has at least one free slot.
 */
static inline int uart_tx_ready(void)
{
    return (UART_LSR & LSR_THRE) != 0U;
}

/**
 * uart_tx_empty() – returns non-zero if TX shift register is completely empty.
 */
static inline int uart_tx_empty(void)
{
    return (UART_LSR & LSR_TEMT) != 0U;
}

/**
 * uart_rx_ready() – returns non-zero if at least one RX byte is waiting.
 * NOTE: LSR[0] (DR) is only set when IER[0] (RX_IRQ_EN) is also set,
 *       per the RTL:  DR = ~rx_fifo_empty & uart_irq_en_int
 */
static inline int uart_rx_ready(void)
{
    return (UART_LSR & LSR_DR) != 0U;
}

/**
 * uart_putc() – blocking transmit of one byte.
 */
static inline void uart_putc(char c)
{
    while (!uart_tx_ready())
        ;
    UART_THR = (uint32_t)(uint8_t)c;
}

/**
 * uart_puts() – blocking transmit of a null-terminated string.
 */
static inline void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

/**
 * uart_getc() – blocking receive of one byte.
 */
static inline char uart_getc(void)
{
    while (!uart_rx_ready())
        ;
    return (char)(UART_RBR & 0xFFU);
}

/**
 * uart_irq_enable() – enable RX data-ready interrupt.
 */
static inline void uart_irq_enable(void)
{
    UART_IER = IER_RX_IRQ_EN;
}

/**
 * uart_irq_disable() – disable RX interrupt.
 */
static inline void uart_irq_disable(void)
{
    UART_IER = 0x00U;
}

#endif /* UART_H */
