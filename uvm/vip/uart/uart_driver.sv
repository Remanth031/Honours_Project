// =============================================================================
// uart_driver.sv – UART Serial Driver (Transmits to DUT uart_rx)
// =============================================================================
`ifndef UART_DRIVER_SV
`define UART_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import uart_types_pkg::*;

class uart_driver extends uvm_driver #(uart_seq_item);
    `uvm_component_utils(uart_driver)

    virtual uart_if vif;

    function new(string name = "uart_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        vif.uart_rx <= 1'b1; // Idle line is HIGH
        @(posedge vif.rst_n);
        `uvm_info("UART_DRV", "UART Driver active and initialized", UVM_MEDIUM)

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info("UART_DRV", $sformatf("Transmitting byte to DUT: %s", req.convert2string()), UVM_HIGH)

            transmit_byte(req);

            seq_item_port.item_done();
        end
    endtask

    virtual task transmit_byte(uart_seq_item item);
        int baud_cycles;
        bit parity_calc;

        baud_cycles = item.baud_divisor + 1;

        // 1. Start Bit (Low)
        vif.uart_rx <= 1'b0;
        repeat (baud_cycles) @(posedge vif.clk);

        // 2. 8 Data Bits (LSB first)
        for (int i = 0; i < 8; i++) begin
            vif.uart_rx <= item.payload[i];
            repeat (baud_cycles) @(posedge vif.clk);
        end

        // 3. Optional Parity Bit
        if (item.parity != UART_PARITY_NONE) begin
            parity_calc = ^item.payload; // Even parity
            if (item.parity == UART_PARITY_ODD) parity_calc = ~parity_calc;
            if (item.inject_parity_err) parity_calc = ~parity_calc;

            vif.uart_rx <= parity_calc;
            repeat (baud_cycles) @(posedge vif.clk);
        end

        // 4. Stop Bit(s) (High)
        vif.uart_rx <= item.inject_frame_err ? 1'b0 : 1'b1;
        repeat (baud_cycles) @(posedge vif.clk);

        if (item.stop_bits == UART_STOP_2BIT) begin
            vif.uart_rx <= 1'b1;
            repeat (baud_cycles) @(posedge vif.clk);
        end

        // Inter-character idle delay (1 bit period)
        vif.uart_rx <= 1'b1;
        repeat (baud_cycles) @(posedge vif.clk);
    endtask

endclass : uart_driver

`endif // UART_DRIVER_SV
