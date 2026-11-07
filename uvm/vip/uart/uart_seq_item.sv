// =============================================================================
// uart_seq_item.sv – UART Transaction Sequence Item
// =============================================================================
`ifndef UART_SEQ_ITEM_SV
`define UART_SEQ_ITEM_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import uart_types_pkg::*;

class uart_seq_item extends uvm_sequence_item;

    rand bit [7:0]          payload;
    rand uart_parity_e      parity;
    rand uart_stop_e        stop_bits;
    rand int unsigned       baud_divisor;
    rand bit                inject_parity_err;
    rand bit                inject_frame_err;

    constraint c_baud {
        baud_divisor inside {[4:64]};
    }

    constraint c_parity {
        parity == UART_PARITY_NONE;
    }

    constraint c_stop {
        stop_bits == UART_STOP_1BIT;
    }

    constraint c_err {
        inject_parity_err == 1'b0;
        inject_frame_err  == 1'b0;
    }

    `uvm_object_utils_begin(uart_seq_item)
        `uvm_field_int(payload, UVM_ALL_ON | UVM_HEX)
        `uvm_field_enum(uart_parity_e, parity, UVM_ALL_ON)
        `uvm_field_enum(uart_stop_e, stop_bits, UVM_ALL_ON)
        `uvm_field_int(baud_divisor, UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "uart_seq_item");
        super.new(name);
        payload = 8'h00;
        parity = UART_PARITY_NONE;
        stop_bits = UART_STOP_1BIT;
        baud_divisor = 16;
        inject_parity_err = 0;
        inject_frame_err = 0;
    endfunction

    virtual function string convert2string();
        return $sformatf("UART_ITEM: DATA=0x%02h ('%c') PARITY=%s STOP=%s BAUD_DIV=%0d",
                         payload, (payload >= 32 && payload <= 126) ? payload : ".",
                         parity.name(), stop_bits.name(), baud_divisor);
    endfunction

endclass : uart_seq_item

`endif // UART_SEQ_ITEM_SV
