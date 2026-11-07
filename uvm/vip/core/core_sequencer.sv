// =============================================================================
// core_sequencer.sv – Core Master Sequencer
// =============================================================================
`ifndef CORE_SEQUENCER_SV
`define CORE_SEQUENCER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import core_types_pkg::*;

class core_sequencer extends uvm_sequencer #(core_seq_item);
    `uvm_component_utils(core_sequencer)

    function new(string name = "core_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass : core_sequencer

`endif // CORE_SEQUENCER_SV
