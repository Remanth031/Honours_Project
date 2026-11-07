// =============================================================================
// axi_vip_pkg.sv – AXI4 Verification IP Package
// =============================================================================
`ifndef AXI_VIP_PKG_SV
`define AXI_VIP_PKG_SV

`include "uvm_macros.svh"

package axi_vip_pkg;
    import uvm_pkg::*;
    import axi_types_pkg::*;

    `include "axi_seq_item.sv"
    `include "axi_sequencer.sv"
    `include "axi_master_driver.sv"
    `include "axi_monitor.sv"
    `include "axi_master_agent.sv"
endpackage : axi_vip_pkg

`endif // AXI_VIP_PKG_SV
