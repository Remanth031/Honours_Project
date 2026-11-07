// =============================================================================
// veer_el2_stub.v  –  VeeR EL2 RV32IMC CPU Master (AXI4 stub)
// Interconnect port: S00
// Accesses: Data Memory, Framebuffer, AR Control, HPM, VGA Ctrl Regs
//
// This is a stub that models the AXI4 master port of the VeeR EL2 core.
// The actual full VeeR EL2 core implementation is integrated in veer_el2_top.sv.
// This stub is retained as a lightweight simulation/tie-off fallback if needed.
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module veer_el2_stub #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8
)(
    input  wire                  clk,
    input  wire                  rst_l,      // active-low reset (VeeR convention)

    // ---- External interrupt inputs ----
    input  wire                  ar_irq,     // from AR Control
    input  wire [7:0]            ext_int,    // external interrupts:
                                             //   [0] = UART RX interrupt
                                             //   [1] = GPIO interrupt
                                             //   [2] = SPI transfer done
                                             //   [3] = Timer A interrupt
                                             //   [4] = Timer B interrupt
                                             //   [5] = Watchdog pre-warning IRQ
                                             //   [7:6] = reserved (tied to 0)

    // ---- AXI4 Master Interface (LSU port → interconnect S00) ----
    // Write address channel
    output wire [ID_WIDTH-1:0]   m_axi_awid,
    output wire [ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]            m_axi_awlen,
    output wire [2:0]            m_axi_awsize,
    output wire [1:0]            m_axi_awburst,
    output wire                  m_axi_awlock,
    output wire [3:0]            m_axi_awcache,
    output wire [2:0]            m_axi_awprot,
    output wire [3:0]            m_axi_awqos,
    output wire                  m_axi_awvalid,
    input  wire                  m_axi_awready,
    // Write data channel
    output wire [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [STRB_WIDTH-1:0] m_axi_wstrb,
    output wire                  m_axi_wlast,
    output wire                  m_axi_wvalid,
    input  wire                  m_axi_wready,
    // Write response channel
    input  wire [ID_WIDTH-1:0]   m_axi_bid,
    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output wire                  m_axi_bready,
    // Read address channel
    output wire [ID_WIDTH-1:0]   m_axi_arid,
    output wire [ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [7:0]            m_axi_arlen,
    output wire [2:0]            m_axi_arsize,
    output wire [1:0]            m_axi_arburst,
    output wire                  m_axi_arlock,
    output wire [3:0]            m_axi_arcache,
    output wire [2:0]            m_axi_arprot,
    output wire [3:0]            m_axi_arqos,
    output wire                  m_axi_arvalid,
    input  wire                  m_axi_arready,
    // Read data channel
    input  wire [ID_WIDTH-1:0]   m_axi_rid,
    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output wire                  m_axi_rready
);

// =========================================================================
// STUB: All master outputs driven to idle/no-transaction state.
// Replace with actual VeeR EL2 el2_veer_wrapper instantiation.
// =========================================================================

// Tie-off: no transactions issued
assign m_axi_awid    = {ID_WIDTH{1'b0}};
assign m_axi_awaddr  = {ADDR_WIDTH{1'b0}};
assign m_axi_awlen   = 8'h00;
assign m_axi_awsize  = 3'b010;   // 4-byte word
assign m_axi_awburst = 2'b01;    // INCR
assign m_axi_awlock  = 1'b0;
assign m_axi_awcache = 4'b0000;
assign m_axi_awprot  = 3'b000;
assign m_axi_awqos   = 4'h0;
assign m_axi_awvalid = 1'b0;

assign m_axi_wdata   = {DATA_WIDTH{1'b0}};
assign m_axi_wstrb   = {STRB_WIDTH{1'b0}};
assign m_axi_wlast   = 1'b0;
assign m_axi_wvalid  = 1'b0;

assign m_axi_bready  = 1'b1;

assign m_axi_arid    = {ID_WIDTH{1'b0}};
assign m_axi_araddr  = {ADDR_WIDTH{1'b0}};
assign m_axi_arlen   = 8'h00;
assign m_axi_arsize  = 3'b010;
assign m_axi_arburst = 2'b01;
assign m_axi_arlock  = 1'b0;
assign m_axi_arcache = 4'b0000;
assign m_axi_arprot  = 3'b000;
assign m_axi_arqos   = 4'h0;
assign m_axi_arvalid = 1'b0;

assign m_axi_rready  = 1'b1;

endmodule

`resetall
