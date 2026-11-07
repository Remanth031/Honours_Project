// =============================================================================
// tb_soc_uvm_top.sv – Top-Level UVM Testbench for AXI Interconnect & UART Subsystem
// =============================================================================
`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

import axi_types_pkg::*;
import uart_types_pkg::*;
import axi_vip_pkg::*;
import uart_vip_pkg::*;
import soc_env_pkg::*;
`include "soc_tests.sv"

module tb_soc_uvm_top;

    // Clock and Reset Signals
    logic clk;
    logic rst_n;

    // Clock Generation: 100 MHz (10ns period)
    initial begin
        clk = 1'b0;
        forever #5ns clk = ~clk;
    end

    // Reset Generation: Active-low reset asserted for 50ns
    initial begin
        rst_n = 1'b0;
        #50ns;
        @(posedge clk);
        rst_n = 1'b1;
        `uvm_info("TB_TOP", "System Reset De-asserted", UVM_LOW)
    end

    // Physical Interfaces
    axi_if #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32),
        .STRB_WIDTH (4),
        .ID_WIDTH   (8)
    ) axi_bus (
        .clk   (clk),
        .rst_n (rst_n)
    );

    uart_if uart_bus (
        .clk   (clk),
        .rst_n (rst_n)
    );

    // DUT Subsystem Instantiation
    soc_uart_subsystem #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (32),
        .STRB_WIDTH (4),
        .ID_WIDTH   (8)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),

        // S00: AXI Master Port (Core Initiator / AXI VIP)
        .s00_axi_awid    (axi_bus.awid),
        .s00_axi_awaddr  (axi_bus.awaddr),
        .s00_axi_awlen   (axi_bus.awlen),
        .s00_axi_awsize  (axi_bus.awsize),
        .s00_axi_awburst (axi_bus.awburst),
        .s00_axi_awlock  (axi_bus.awlock),
        .s00_axi_awcache (axi_bus.awcache),
        .s00_axi_awprot  (axi_bus.awprot),
        .s00_axi_awqos   (axi_bus.awqos),
        .s00_axi_awvalid (axi_bus.awvalid),
        .s00_axi_awready (axi_bus.awready),

        .s00_axi_wdata   (axi_bus.wdata),
        .s00_axi_wstrb   (axi_bus.wstrb),
        .s00_axi_wlast   (axi_bus.wlast),
        .s00_axi_wvalid  (axi_bus.wvalid),
        .s00_axi_wready  (axi_bus.wready),

        .s00_axi_bid     (axi_bus.bid),
        .s00_axi_bresp   (axi_bus.bresp),
        .s00_axi_bvalid  (axi_bus.bvalid),
        .s00_axi_bready  (axi_bus.bready),

        .s00_axi_arid    (axi_bus.arid),
        .s00_axi_araddr  (axi_bus.araddr),
        .s00_axi_arlen   (axi_bus.arlen),
        .s00_axi_arsize  (axi_bus.arsize),
        .s00_axi_arburst (axi_bus.arburst),
        .s00_axi_arlock  (axi_bus.arlock),
        .s00_axi_arcache (axi_bus.arcache),
        .s00_axi_arprot  (axi_bus.arprot),
        .s00_axi_arqos   (axi_bus.arqos),
        .s00_axi_arvalid (axi_bus.arvalid),
        .s00_axi_arready (axi_bus.arready),

        .s00_axi_rid     (axi_bus.rid),
        .s00_axi_rdata   (axi_bus.rdata),
        .s00_axi_rresp   (axi_bus.rresp),
        .s00_axi_rlast   (axi_bus.rlast),
        .s00_axi_rvalid  (axi_bus.rvalid),
        .s00_axi_rready  (axi_bus.rready),

        // UART Serial Pins
        .uart_rx         (uart_bus.uart_rx),
        .uart_tx         (uart_bus.uart_tx),
        .uart_irq        (uart_bus.uart_irq)
    );

    // Initial Block: Configure DB, dump waveforms, and run test
    initial begin
        // Store virtual interfaces into UVM config DB
        uvm_config_db#(virtual axi_if)::set(null, "*.m_axi_agent*", "vif", axi_bus);
        uvm_config_db#(virtual uart_if)::set(null, "*.m_uart_agent*", "vif", uart_bus);

        // Waveform Dumping for Verdi / VCS DVE
        $dumpfile("soc_uvm.vcd");
        $dumpvars(0, tb_soc_uvm_top);

        // Start UVM Phase Execution
        run_test();
    end

endmodule
