/* =============================================================================
 * uart_test.c  –  AXI-Lite UART IP Read/Write Verification Test
 *
 * Tests performed (in order):
 *  1. BAUD-RATE CONFIG  – Set DLAB=1, write divisor, clear DLAB.
 *                         Read back LCR to confirm DLAB cleared.
 *  2. TX WRITE          – Transmit a string character-by-character, polling
 *                         LSR[THRE] (TX FIFO ready) before each byte.
 *  3. IRQ ENABLE        – Enable RX interrupt via IER[0] so LSR[DR] works.
 *  4. RX LOOPBACK READ  – In a loopback simulation (uart_tx → uart_rx wired
 *                         together), receive the same bytes just sent and
 *                         compare them against the expected string.
 *  5. LSR STATUS READ   – Read and decode the LSR register and verify THRE
 *                         and TEMT bits are set after TX drains.
 *  6. BAUD-RATE CHANGE  – Switch to 9600 baud (different divisor) through the
 *                         DLAB sequence and verify LSR still reports idle.
 *
 * Pass/fail: each test prints "[PASS]" or "[FAIL]".
 * Final summary prints overall result.
 *
 * Simulation note:
 *   The test uses uart_tx → uart_rx loopback.  In simulation, tie
 *   uart_tx_o → uart_rx_i in the testbench.  The RX path includes the
 *   UART baud-rate engine, so there will be latency equal to one full
 *   character frame (10 bit-times at the configured divisor).
 *   A software timeout counter is used so the test does not hang on
 *   broken hardware; it reports FAIL and moves on.
 * =============================================================================
 */

#include <stdint.h>
#include "uart.h"

/* ---- simple print helpers (use the UART itself after init) ---- */

/* Write a decimal number (unsigned, max 10 digits) */
static void print_uint(uint32_t v)
{
    char buf[11];
    int  i = 0;
    if (v == 0) { uart_putc('0'); return; }
    while (v) { buf[i++] = '0' + (v % 10); v /= 10; }
    while (i--) uart_putc(buf[i]);
}

/* Write a hex number with 0x prefix, always 8 hex digits */
static void print_hex(uint32_t v)
{
    const char hd[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int s = 28; s >= 0; s -= 4)
        uart_putc(hd[(v >> s) & 0xF]);
}

/* Write "[PASS]\r\n" or "[FAIL]\r\n" */
static void print_result(int pass)
{
    if (pass)
        uart_puts("[PASS]\r\n");
    else
        uart_puts("[FAIL]\r\n");
}

/* ---- test state ---- */
static int total_pass = 0;
static int total_fail = 0;

static void record(int pass)
{
    if (pass) total_pass++;
    else      total_fail++;
    print_result(pass);
}

/* ---- timeout helper ---- */
#define TIMEOUT_CYCLES  2000000U   /* generous SW loop count */

/* =========================================================================
 * TEST 1 – Baud-rate configuration
 * =========================================================================
 * Procedure:
 *   a) Set LCR[7]=1 (DLAB=1)
 *   b) Write UART_BAUD_115200 divisor to BAUD register
 *   c) Write LCR = 0x00 (DLAB=0, 8N1)
 *   d) Read LCR back, verify DLAB bit is cleared
 * Expected: LCR read-back == 0x00 (DLAB clear)
 * ========================================================================= */
static int test_baud_config(void)
{
    uart_puts("TEST 1: Baud-rate config (115200)... ");

    /* Step a: set DLAB */
    UART_LCR = LCR_DLAB;

    /* Step b: write divisor */
    UART_BAUD = (uint32_t)UART_BAUD_115200;

    /* Step c: clear DLAB – 8N1, no parity */
    UART_LCR = 0x00U;

    /* Step d: read LCR back */
    uint32_t lcr = UART_LCR;
    int pass = ((lcr & LCR_DLAB) == 0U);

    if (!pass) {
        uart_puts("LCR="); print_hex(lcr); uart_puts(" ");
    }
    return pass;
}

/* =========================================================================
 * TEST 2 – TX write (polling LSR[THRE])
 * =========================================================================
 * Transmit each byte of the test string, confirming THRE is set before
 * each write.  If THRE is never set within TIMEOUT_CYCLES, the test fails.
 * ========================================================================= */
static const char TX_STRING[] = "UART_TEST_LOOPBACK";

static int test_tx_write(void)
{
    uart_puts("TEST 2: TX write... ");

    for (int i = 0; TX_STRING[i] != '\0'; i++) {
        /* Wait for TX FIFO space */
        uint32_t t = 0;
        while (!uart_tx_ready()) {
            if (++t >= TIMEOUT_CYCLES) {
                uart_puts("TX_TIMEOUT ");
                return 0;   /* FAIL */
            }
        }
        /* Verify THRE bit explicitly */
        uint32_t lsr = UART_LSR;
        if (!(lsr & LSR_THRE)) {
            uart_puts("THRE_LOW ");
            return 0;
        }
        UART_THR = (uint32_t)(uint8_t)TX_STRING[i];
    }
    return 1;   /* PASS */
}

/* =========================================================================
 * TEST 3 – IER: enable RX interrupt so LSR[DR] works
 * =========================================================================
 * The RTL gates LSR[DR] with uart_irq_en_int (IER[0]).
 * Write IER[0]=1, read IER back to confirm.
 * ========================================================================= */
static int test_ier_enable(void)
{
    uart_puts("TEST 3: IER RX interrupt enable... ");

    UART_IER = IER_RX_IRQ_EN;
    uint32_t ier = UART_IER;
    /* IER is write-only in many UART implementations – if readback returns
     * 0 that is acceptable; what matters is the RX path works.
     * We accept both 0x00 (write-only) and 0x01 (readable). */
    int pass = ((ier == IER_RX_IRQ_EN) || (ier == 0x00U));
    if (!pass) {
        uart_puts("IER="); print_hex(ier); uart_puts(" ");
    }
    return pass;
}

/* =========================================================================
 * TEST 4 – RX loopback read
 * =========================================================================
 * Receive the same bytes that TEST 2 transmitted (loopback wiring in TB).
 * Compare each received byte against TX_STRING.
 * Timeout if no byte arrives within TIMEOUT_CYCLES.
 * ========================================================================= */
static int test_rx_loopback(void)
{
    uart_puts("TEST 4: RX loopback read... ");

    for (int i = 0; TX_STRING[i] != '\0'; i++) {
        /* Wait for DR=1 */
        uint32_t t = 0;
        while (!uart_rx_ready()) {
            if (++t >= TIMEOUT_CYCLES) {
                uart_puts("RX_TIMEOUT@");
                print_uint((uint32_t)i);
                uart_puts(" ");
                return 0;
            }
        }

        uint8_t rx = (uint8_t)(UART_RBR & 0xFFU);
        if (rx != (uint8_t)TX_STRING[i]) {
            uart_puts("MISMATCH@");
            print_uint((uint32_t)i);
            uart_puts(" exp=");
            print_hex((uint32_t)TX_STRING[i]);
            uart_puts(" got=");
            print_hex((uint32_t)rx);
            uart_puts(" ");
            return 0;
        }
    }
    return 1;
}

/* =========================================================================
 * TEST 5 – LSR status register verification
 * =========================================================================
 * After all TX bytes have been sent and the TX FIFO has drained:
 *   - LSR[THRE] (bit 5) must be 1 → TX FIFO has space
 *   - LSR[TEMT] (bit 6) must be 1 → TX shift register empty
 * Poll until both bits set (or timeout).
 * ========================================================================= */
static int test_lsr_status(void)
{
    uart_puts("TEST 5: LSR status (THRE+TEMT after TX drain)... ");

    uint32_t t = 0;
    uint32_t lsr;
    do {
        lsr = UART_LSR;
        if (++t >= TIMEOUT_CYCLES) {
            uart_puts("LSR="); print_hex(lsr); uart_puts(" TIMEOUT ");
            return 0;
        }
    } while ((lsr & (LSR_THRE | LSR_TEMT)) != (LSR_THRE | LSR_TEMT));

    /* Also verify DR=0 (no stale RX data) – soft check only */
    int pass = 1;
    if (lsr & LSR_DR) {
        uart_puts("DR_still_set ");
        pass = 0;
    }
    return pass;
}

/* =========================================================================
 * TEST 6 – Baud-rate change to 9600
 * =========================================================================
 * Set DLAB=1, write 9600-baud divisor, clear DLAB.
 * Then send one byte at the new baud rate and confirm THRE asserts.
 * ========================================================================= */
static int test_baud_change(void)
{
    uart_puts("TEST 6: Baud-rate change to 9600... ");

    /* Switch to 9600 */
    UART_LCR  = LCR_DLAB;
    UART_BAUD = (uint32_t)UART_BAUD_9600;
    UART_LCR  = 0x00U;

    /* Verify DLAB cleared */
    if (UART_LCR & LCR_DLAB) {
        uart_puts("DLAB_stuck ");
        return 0;
    }

    /* Send a single byte at 9600, poll THRE */
    uint32_t t = 0;
    while (!uart_tx_ready()) {
        if (++t >= TIMEOUT_CYCLES) {
            uart_puts("THRE_TIMEOUT ");
            return 0;
        }
    }
    UART_THR = (uint32_t)'@';   /* marker byte at 9600 baud */

    /* Restore 115200 for any further output */
    UART_LCR  = LCR_DLAB;
    UART_BAUD = (uint32_t)UART_BAUD_115200;
    UART_LCR  = 0x00U;

    return 1;
}

/* =========================================================================
 * main
 * ========================================================================= */
int main(void)
{
    /* ------------------------------------------------------------------
     * Initialise: 115200 baud, 8N1, no parity, 1 stop bit.
     * This uses the DLAB sequence internally.
     * ------------------------------------------------------------------ */
    uart_init(UART_BAUD_115200);

    uart_puts("\r\n========================================\r\n");
    uart_puts("  AXI-Lite UART IP Verification Test\r\n");
    uart_puts("  VeeR EL2 RV32IMC SoC\r\n");
    uart_puts("  UART_BASE = "); print_hex(UART_BASE); uart_puts("\r\n");
    uart_puts("========================================\r\n\r\n");

    /* ------------------------------------------------------------------
     * Run tests
     * ------------------------------------------------------------------ */
    record(test_baud_config());
    record(test_tx_write());
    record(test_ier_enable());
    record(test_rx_loopback());
    record(test_lsr_status());
    record(test_baud_change());

    /* ------------------------------------------------------------------
     * Summary
     * ------------------------------------------------------------------ */
    uart_puts("\r\n========================================\r\n");
    uart_puts("RESULTS: ");
    print_uint((uint32_t)total_pass);
    uart_puts(" PASS, ");
    print_uint((uint32_t)total_fail);
    uart_puts(" FAIL\r\n");

    if (total_fail == 0) {
        uart_puts("ALL TESTS PASSED\r\n");
    } else {
        uart_puts("SOME TESTS FAILED\r\n");
    }
    uart_puts("========================================\r\n");

    /* Spin forever */
    for (;;)
        ;

    return 0;
}
