// =============================================================================
// core_master_agent.sv – Core Master UVM Agent
// =============================================================================
`ifndef CORE_MASTER_AGENT_SV
`define CORE_MASTER_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import core_types_pkg::*;

class core_master_agent extends uvm_agent;
    `uvm_component_utils(core_master_agent)

    core_sequencer     sequencer;
    core_master_driver driver;
    core_monitor       monitor;

    function new(string name = "core_master_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = core_monitor::type_id::create("monitor", this);

        if (get_is_active() == UVM_ACTIVE) begin
            sequencer = core_sequencer::type_id::create("sequencer", this);
            driver    = core_master_driver::type_id::create("driver", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : core_master_agent

`endif // CORE_MASTER_AGENT_SV
