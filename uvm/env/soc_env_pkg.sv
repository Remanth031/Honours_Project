// =============================================================================
// soc_env_pkg.sv – Subsystem Environment Package
// =============================================================================
`ifndef SOC_ENV_PKG_SV
`define SOC_ENV_PKG_SV

`include "uvm_macros.svh"

package soc_env_pkg;
    import uvm_pkg::*;
    import axi_types_pkg::*;
    import uart_types_pkg::*;
    import axi_vip_pkg::*;
    import uart_vip_pkg::*;

    `include "soc_scoreboard.sv"
    `include "soc_env.sv"
endpackage : soc_env_pkg

`endif // SOC_ENV_PKG_SV
