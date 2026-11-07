// =============================================================================
// axi_master_agent.sv – AXI4 Master Agent
// =============================================================================
`ifndef AXI_MASTER_AGENT_SV
`define AXI_MASTER_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_types_pkg::*;

class axi_master_agent extends uvm_agent;
    `uvm_component_utils(axi_master_agent)

    axi_sequencer     sequencer;
    axi_master_driver driver;
    axi_monitor       monitor;

    function new(string name = "axi_master_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = axi_monitor::type_id::create("monitor", this);

        if (get_is_active() == UVM_ACTIVE) begin
            sequencer = axi_sequencer::type_id::create("sequencer", this);
            driver    = axi_master_driver::type_id::create("driver", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : axi_master_agent

`endif // AXI_MASTER_AGENT_SV
