// =============================================================================
// axi_seq_item.sv – AXI4 Transaction Sequence Item
// =============================================================================
`ifndef AXI_SEQ_ITEM_SV
`define AXI_SEQ_ITEM_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_types_pkg::*;

class axi_seq_item extends uvm_sequence_item;

    rand bit [31:0]         addr;
    rand bit [31:0]         data[];
    rand bit [3:0]          strb[];
    rand axi_rw_e           rw;
    rand bit [7:0]          id;
    rand bit [7:0]          len;       // 0 = 1 beat, 1 = 2 beats, etc.
    rand axi_size_e         size;
    rand axi_burst_e        burst;
    rand int unsigned       addr_delay;
    rand int unsigned       data_delay;

    axi_resp_e              resp[];

    // Constraints
    constraint c_len {
        len inside {[0:15]};
    }

    constraint c_size {
        size == AXI_SIZE_4_BYTES;
    }

    constraint c_burst {
        burst == AXI_BURST_INCR;
    }

    constraint c_addr_align {
        addr[1:0] == 2'b00; // 32-bit word aligned
    }

    constraint c_data_size {
        data.size() == (len + 1);
        strb.size() == (len + 1);
    }

    constraint c_delays {
        addr_delay inside {[0:4]};
        data_delay inside {[0:4]};
    }

    `uvm_object_utils_begin(axi_seq_item)
        `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
        `uvm_field_array_int(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_array_int(strb, UVM_ALL_ON | UVM_BIN)
        `uvm_field_enum(axi_rw_e, rw, UVM_ALL_ON)
        `uvm_field_int(id, UVM_ALL_ON)
        `uvm_field_int(len, UVM_ALL_ON | UVM_DEC)
        `uvm_field_enum(axi_size_e, size, UVM_ALL_ON)
        `uvm_field_enum(axi_burst_e, burst, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi_seq_item");
        super.new(name);
        data = new[1];
        strb = new[1];
        strb[0] = 4'b1111;
        resp = new[1];
        resp[0] = AXI_RESP_OKAY;
        rw = AXI_WRITE;
        len = 0;
        size = AXI_SIZE_4_BYTES;
        burst = AXI_BURST_INCR;
    endfunction

    virtual function string convert2string();
        string s;
        s = $sformatf("AXI_TR [%s] ID=0x%0h ADDR=0x%08h LEN=%0d DATA=[",
                      (rw == AXI_WRITE) ? "WRITE" : "READ", id, addr, len);
        for (int i = 0; i < data.size(); i++) begin
            s = {s, $sformatf(" 0x%08h", data[i])};
        end
        s = {s, $sformatf(" ] RESP=%s", (resp.size() > 0) ? resp[0].name() : "NONE")};
        return s;
    endfunction

endclass : axi_seq_item

`endif // AXI_SEQ_ITEM_SV
