// =============================================================================
// tb_core_uart_uvm_top.sv – Direct Core-to-UART UVM Testbench Top
// =============================================================================
`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

import core_types_pkg::*;
import uart_types_pkg::*;
import core_vip_pkg::*;
import uart_vip_pkg::*;
import core_uart_env_pkg::*;
`include "core_uart_tests.sv"

module tb_core_uart_uvm_top;

    logic clk;
    logic rst_n;

    // Clock Generation: 100 MHz (10ns period)
    initial begin
        clk = 1'b0;
        forever #5ns clk = ~clk;
    end

    // Reset Generation: 50ns active-low reset pulse
    initial begin
        rst_n = 1'b0;
        #50ns;
        @(posedge clk);
        rst_n = 1'b1;
        `uvm_info("TB_TOP", "System Reset De-asserted (Direct Core-to-UART)", UVM_LOW)
    end

    // Direct Core Physical Interface
    core_if #(
        .ADDR_WIDTH (5),
        .DATA_WIDTH (32),
        .STRB_WIDTH (4)
    ) core_bus (
        .clk   (clk),
        .rst_n (rst_n)
    );

    // UART Physical Serial Interface
    uart_if uart_bus (
        .clk   (clk),
        .rst_n (rst_n)
    );

    // DUT Instantiation: DIRECT Core-to-UART (Zero Interconnect in between)
    core_uart_direct_top dut (
        .clk          (clk),
        .rst_n        (rst_n),

        // Direct Core Write Channel
        .core_awaddr  (core_bus.awaddr),
        .core_awvalid (core_bus.awvalid),
        .core_awready (core_bus.awready),
        .core_wdata   (core_bus.wdata),
        .core_wstrb   (core_bus.wstrb),
        .core_wvalid  (core_bus.wvalid),
        .core_wready  (core_bus.wready),
        .core_bresp   (core_bus.bresp),
        .core_bvalid  (core_bus.bvalid),
        .core_bready  (core_bus.bready),

        // Direct Core Read Channel
        .core_araddr  (core_bus.araddr),
        .core_arvalid (core_bus.arvalid),
        .core_arready (core_bus.arready),
        .core_rdata   (core_bus.rdata),
        .core_rresp   (core_bus.rresp),
        .core_rvalid  (core_bus.rvalid),
        .core_rready  (core_bus.rready),

        // Serial pins
        .uart_rx      (uart_bus.uart_rx),
        .uart_tx      (uart_bus.uart_tx),
        .uart_irq     (uart_bus.uart_irq)
    );

    initial begin
        // Configure virtual interfaces in DB
        uvm_config_db#(virtual core_if)::set(null, "*.m_core_agent*", "vif", core_bus);
        uvm_config_db#(virtual uart_if)::set(null, "*.m_uart_agent*", "vif", uart_bus);

        // Waveform trace dump
        $dumpfile("core_uart_uvm.vcd");
        $dumpvars(0, tb_core_uart_uvm_top);

        // Run Unified Single UVM Testbench (Runs all tests)
        run_test("core_uart_unified_test");
    end

endmodule
