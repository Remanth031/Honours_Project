// =============================================================================
// uart_types_pkg.sv – UART VIP Types & Definitions
// =============================================================================
`ifndef UART_TYPES_PKG_SV
`define UART_TYPES_PKG_SV

package uart_types_pkg;

    typedef enum bit [1:0] {
        UART_PARITY_NONE = 2'b00,
        UART_PARITY_ODD  = 2'b01,
        UART_PARITY_EVEN = 2'b10
    } uart_parity_e;

    typedef enum bit {
        UART_STOP_1BIT = 1'b0,
        UART_STOP_2BIT = 1'b1
    } uart_stop_e;

endpackage : uart_types_pkg

`endif // UART_TYPES_PKG_SV
