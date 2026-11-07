// =============================================================================
// uart_if.sv – UART Physical Serial Interface Definition
// =============================================================================
`ifndef UART_IF_SV
`define UART_IF_SV

interface uart_if(
    input logic clk,
    input logic rst_n
);
    logic uart_rx; // Driven into DUT
    logic uart_tx; // Monitored from DUT
    logic uart_irq;// Interrupt line from DUT

    // Modports
    modport dut (
        input  uart_rx,
        output uart_tx,
        output uart_irq
    );

    modport tb (
        output uart_rx,
        input  uart_tx,
        input  uart_irq
    );

endinterface : uart_if

`endif // UART_IF_SV
