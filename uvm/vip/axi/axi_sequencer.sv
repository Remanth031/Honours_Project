// =============================================================================
// axi_sequencer.sv – AXI4 Sequencer
// =============================================================================
`ifndef AXI_SEQUENCER_SV
`define AXI_SEQUENCER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_types_pkg::*;

class axi_sequencer extends uvm_sequencer #(axi_seq_item);
    `uvm_component_utils(axi_sequencer)

    function new(string name = "axi_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass : axi_sequencer

`endif // AXI_SEQUENCER_SV
