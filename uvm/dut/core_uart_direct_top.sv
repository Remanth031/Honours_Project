// =============================================================================
// core_uart_direct_top.sv – Direct Core-to-UART Subsystem (Zero AXI Interconnect)
// =============================================================================
// Architecture:
//   Core Master Port (Read/Write signals directly from CPU/VIP)
//              |
//              +----> Direct point-to-point connection (NO Interconnect)
//              |
//              v
//   axi_uart_top (UART IP Core)
//              |
//              +----> uart_rx / uart_tx / uart_irq (to UART VIP)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype wire

module core_uart_direct_top (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Core Direct Write Channel ----
    input  wire [4:0]  core_awaddr,
    input  wire        core_awvalid,
    output wire        core_awready,
    input  wire [31:0] core_wdata,
    input  wire [3:0]  core_wstrb,
    input  wire        core_wvalid,
    output wire        core_wready,
    output wire [1:0]  core_bresp,
    output wire        core_bvalid,
    input  wire        core_bready,

    // ---- Core Direct Read Channel ----
    input  wire [4:0]  core_araddr,
    input  wire        core_arvalid,
    output wire        core_arready,
    output wire [31:0] core_rdata,
    output wire [1:0]  core_rresp,
    output wire        core_rvalid,
    input  wire        core_rready,

    // ---- UART Serial Interface ----
    input  wire        uart_rx,
    output wire        uart_tx,
    output wire        uart_irq
);

    // Direct instantiation of UART IP Core – NO AXI INTERCONNECT
    axi_uart_top u_uart (
        .fixed_clk_i      (clk),
        .axi_aclk_i       (clk),
        .axi_aresetn_i    (rst_n),

        // Direct Write Channel from Core
        .axi_awid_i       (12'd0),
        .axi_awaddr_i     (core_awaddr),
        .axi_awvalid_i    (core_awvalid),
        .axi_awready_o    (core_awready),

        .axi_wdata_i      (core_wdata),
        .axi_wstrb_i      (core_wstrb),
        .axi_wvalid_i     (core_wvalid),
        .axi_wready_o     (core_wready),

        .axi_bid_o        (),
        .axi_bresp_o      (core_bresp),
        .axi_bvalid_o     (core_bvalid),
        .axi_bready_i     (core_bready),

        // Direct Read Channel from Core
        .axi_arid_i       (12'd0),
        .axi_araddr_i     (core_araddr),
        .axi_arvalid_i    (core_arvalid),
        .axi_arready_o    (core_arready),

        .axi_rid_o        (),
        .axi_rdata_o      (core_rdata),
        .axi_rresp_o      (core_rresp),
        .axi_rvalid_o     (core_rvalid),
        .axi_rready_i     (core_rready),

        // Serial and IRQ lines
        .read_interrupt_o (uart_irq),
        .uart_tx_o       (uart_tx),
        .uart_rx_i       (uart_rx)
    );

endmodule

`default_nettype wire
