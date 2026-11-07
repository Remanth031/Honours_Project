// =============================================================================
// core_vip_pkg.sv – Core Master Verification IP Package
// =============================================================================
`ifndef CORE_VIP_PKG_SV
`define CORE_VIP_PKG_SV

`include "uvm_macros.svh"

package core_vip_pkg;
    import uvm_pkg::*;
    import core_types_pkg::*;

    `include "core_seq_item.sv"
    `include "core_sequencer.sv"
    `include "core_master_driver.sv"
    `include "core_monitor.sv"
    `include "core_master_agent.sv"
endpackage : core_vip_pkg

`endif // CORE_VIP_PKG_SV
