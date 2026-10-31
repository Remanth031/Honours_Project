/* startup.S – Minimal bare-metal startup for VeeR EL2 RV32IMC
 *
 * - Sets up the stack pointer
 * - Zeroes the .bss section
 * - Jumps to main()
 * - Traps on return (should never happen)
 */

    .section .text.startup, "ax", @progbits
    .global _start
    .type   _start, @function

_start:
    /* Set stack pointer to top of SRAM (data memory ends at 0x00FFFFFF) */
    li      sp, 0x00FFFF00

    /* Zero the .bss section */
    la      t0, __bss_start
    la      t1, __bss_end
.bss_loop:
    bge     t0, t1, .bss_done
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       .bss_loop
.bss_done:

    /* Call main */
    call    main

    /* If main returns, loop forever */
.hang:
    j       .hang

    .size _start, . - _start
