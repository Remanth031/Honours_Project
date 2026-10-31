/* hello.c – Bare-metal "Hello, World!" for VeeR EL2 RV32IMC SoC
 *
 * Prints via a simple UART MMIO stub (tx polling loop).
 * UART TX register address matches a typical VeeR EL2 SoC test bench:
 *   0x200000C0  – UART TX data register (write a byte to transmit)
 *   0x200000C4  – UART TX status register (bit 0 = 0 means ready)
 */

#include <stdint.h>

/* UART MMIO addresses */
#define UART_TX_DATA  (*(volatile uint8_t  *)0x200000C0U)
#define UART_TX_STAT  (*(volatile uint32_t *)0x200000C4U)

static void uart_putc(char c)
{
    /* Wait until TX is ready (bit 0 clear = ready) */
    while (UART_TX_STAT & 0x1U)
        ;
    UART_TX_DATA = (uint8_t)c;
}

static void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

int main(void)
{
    uart_puts("Hello, World!\r\n");
    uart_puts("Array Rasterizer SoC – VeeR EL2 RV32IMC\r\n");

    /* Spin forever */
    for (;;)
        ;

    return 0;
}
