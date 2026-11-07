// =============================================================================
// core_uart_env_pkg.sv – Environment Package for Direct Core-to-UART UVM
// =============================================================================
`ifndef CORE_UART_ENV_PKG_SV
`define CORE_UART_ENV_PKG_SV

`include "uvm_macros.svh"

package core_uart_env_pkg;
    import uvm_pkg::*;
    import core_types_pkg::*;
    import uart_types_pkg::*;
    import core_vip_pkg::*;
    import uart_vip_pkg::*;

    `include "core_uart_scoreboard.sv"
    `include "core_uart_env.sv"
endpackage : core_uart_env_pkg

`endif // CORE_UART_ENV_PKG_SV
