// =============================================================================
// uart_vip_pkg.sv – UART Verification IP Package
// =============================================================================
`ifndef UART_VIP_PKG_SV
`define UART_VIP_PKG_SV

`include "uvm_macros.svh"

package uart_vip_pkg;
    import uvm_pkg::*;
    import uart_types_pkg::*;

    `include "uart_seq_item.sv"
    `include "uart_sequencer.sv"
    `include "uart_driver.sv"
    `include "uart_monitor.sv"
    `include "uart_agent.sv"
endpackage : uart_vip_pkg

`endif // UART_VIP_PKG_SV
