// =============================================================================
// uart_monitor.sv – UART Serial Monitor (Receives from DUT uart_tx)
// =============================================================================
`ifndef UART_MONITOR_SV
`define UART_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import uart_types_pkg::*;

class uart_monitor extends uvm_monitor;
    `uvm_component_utils(uart_monitor)

    virtual uart_if vif;
    uvm_analysis_port #(uart_seq_item) item_collected_port;
    int unsigned current_baud_div = 16; // default simulation divisor

    function new(string name = "uart_monitor", uvm_component parent = null);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
        void'(uvm_config_db#(int unsigned)::get(this, "", "baud_divisor", current_baud_div));
    endfunction

    virtual task run_phase(uvm_phase phase);
        uart_seq_item item;
        int baud_cycles;

        @(posedge vif.rst_n);
        `uvm_info("UART_MON", "UART Monitor active", UVM_MEDIUM)

        forever begin
            baud_cycles = current_baud_div + 1;

            // 1. Detect Start Bit falling edge
            @(negedge vif.uart_tx);

            // Wait 0.5 bit period to reach mid-point of start bit
            repeat (baud_cycles / 2) @(posedge vif.clk);
            if (vif.uart_tx !== 1'b0) begin
                `uvm_warning("UART_MON", "False start bit detected, ignoring")
                continue;
            end

            item = uart_seq_item::type_id::create("mon_uart_item");
            item.baud_divisor = current_baud_div;

            // 2. Sample 8 data bits at center of each bit period
            for (int i = 0; i < 8; i++) begin
                repeat (baud_cycles) @(posedge vif.clk);
                item.payload[i] = vif.uart_tx;
            end

            // 3. Sample Stop Bit
            repeat (baud_cycles) @(posedge vif.clk);
            if (vif.uart_tx !== 1'b1) begin
                `uvm_error("UART_MON", $sformatf("Framing error: Stop bit not HIGH (got %b)", vif.uart_tx))
            end

            `uvm_info("UART_MON", $sformatf("Captured TX Serial Byte: 0x%02h ('%c')",
                                           item.payload, (item.payload >= 32 && item.payload <= 126) ? item.payload : "."), UVM_MEDIUM)
            item_collected_port.write(item);
        end
    endtask

    function void set_baud_divisor(int unsigned div);
        current_baud_div = div;
    endfunction

endclass : uart_monitor

`endif // UART_MONITOR_SV
