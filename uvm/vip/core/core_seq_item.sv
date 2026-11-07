// =============================================================================
// core_seq_item.sv – Core Direct Bus Transaction Item
// =============================================================================
`ifndef CORE_SEQ_ITEM_SV
`define CORE_SEQ_ITEM_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import core_types_pkg::*;

class core_seq_item extends uvm_sequence_item;

    rand bit [4:0]          addr;
    rand bit [31:0]         data;
    rand bit [3:0]          strb;
    rand core_op_e          op;
    rand int unsigned       delay;

    core_resp_e             resp;

    constraint c_strb {
        strb == 4'b1111;
    }

    constraint c_delay {
        delay inside {[0:3]};
    }

    `uvm_object_utils_begin(core_seq_item)
        `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(strb, UVM_ALL_ON | UVM_BIN)
        `uvm_field_enum(core_op_e, op, UVM_ALL_ON)
        `uvm_field_enum(core_resp_e, resp, UVM_ALL_ON)
        `uvm_field_int(delay, UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "core_seq_item");
        super.new(name);
        addr  = 5'h00;
        data  = 32'h0;
        strb  = 4'b1111;
        op    = CORE_WRITE;
        resp  = CORE_RESP_OKAY;
        delay = 0;
    endfunction

    virtual function string convert2string();
        return $sformatf("CORE_TR [%s] ADDR=0x%02h DATA=0x%08h RESP=%s",
                         (op == CORE_WRITE) ? "WRITE" : "READ", addr, data, resp.name());
    endfunction

endclass : core_seq_item

`endif // CORE_SEQ_ITEM_SV
