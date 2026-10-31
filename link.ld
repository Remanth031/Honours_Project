/* link.ld – Linker script for Array Rasterizer SoC (VeeR EL2 RV32IMC)
 *
 * Memory map (matches ar_soc_top.v):
 *   Data Memory  : 0x00000000 – 0x00FFFFFF  (16 MB)
 *   Framebuffer  : 0x10000000 – 0x10FFFFFF  (16 MB)
 *   AR Control   : 0x20000000 – 0x20000FFF  ( 4 KB)
 *   HPM          : 0x20010000 – 0x20010FFF  ( 4 KB)
 *   VGA Ctrl Regs: 0x20020000 – 0x20020FFF  ( 4 KB)
 *
 * Code and data both live in Data Memory.
 *   .text  starts at 0x00000000
 *   .data  follows .text
 *   .bss   follows .data
 *   stack  grows down from 0x00FFFF00
 */

ENTRY(_start)

MEMORY
{
    /* 16 MB data memory */
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16M
}

SECTIONS
{
    /* ---- Code ---- */
    .text ORIGIN(RAM) :
    {
        /* Startup first so reset vector lands at 0x00000000 */
        KEEP(*(.text.startup))
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
    } > RAM

    /* ---- Initialised data ---- */
    .data :
    {
        . = ALIGN(4);
        *(.data .data.*)
        . = ALIGN(4);
    } > RAM

    /* ---- Zero-initialised data ---- */
    .bss :
    {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    /* Discard C++ exception tables and debug info to keep output small */
    /DISCARD/ :
    {
        *(.eh_frame)
        *(.debug*)
    }
}
