// =============================================================================
// vga_controller.v  –  VGA Controller AXI4 Master + Display Driver
// Interconnect port: S03
// Accesses: Framebuffer ONLY (reads pixel data for display)
//
// Reads pixels from the framebuffer over AXI4 burst reads, paced by the
// VGA pixel clock, and drives standard VGA timing outputs.
//
// Default timing: 640x480 @ 60 Hz (25.175 MHz pixel clock from sys clk÷N)
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module vga_controller #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter STRB_WIDTH  = (DATA_WIDTH/8),
    parameter ID_WIDTH    = 8,
    // Default 640x480 VGA timing parameters (in pixels)
    parameter H_ACTIVE    = 640,
    parameter H_FP        = 16,
    parameter H_SYNC      = 96,
    parameter H_BP        = 48,
    parameter V_ACTIVE    = 480,
    parameter V_FP        = 10,
    parameter V_SYNC      = 2,
    parameter V_BP        = 33,
    // Pixel clock divider from system clock
    parameter CLK_DIV     = 2   // sys_clk / CLK_DIV = pixel clock (~25 MHz from 50 MHz)
)(
    input  wire                  clk,         // system clock
    input  wire                  rst,

    // ---- Config from vga_ctrl_regs ----
    input  wire        vga_en,
    input  wire [31:0] fb_base,          // framebuffer base address
    input  wire [31:0] fb_stride,        // row stride in bytes

    // Timing parameters from vga_ctrl_regs (dynamic override if configured)
    input  wire        vsync_pol,
    input  wire        hsync_pol,
    input  wire [15:0] h_total,
    input  wire [15:0] h_active,
    input  wire [15:0] v_total,
    input  wire [15:0] v_active,
    input  wire [15:0] h_sync_start,
    input  wire [15:0] h_sync_end,
    input  wire [15:0] v_sync_start,
    input  wire [15:0] v_sync_end,

    // ---- VGA Timing Outputs ----
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        vga_blank_n,
    output wire        vga_sync_n,
    output wire        vga_clk_out,

    // ---- Status back to vga_ctrl_regs ----
    output wire        vsync_active,
    output wire        hsync_active,

    // ---- AXI4 Master Interface (→ interconnect S03, read-only) ----
    // Write path – tied off
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
    output wire [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [STRB_WIDTH-1:0] m_axi_wstrb,
    output wire                  m_axi_wlast,
    output wire                  m_axi_wvalid,
    input  wire                  m_axi_wready,
    input  wire [ID_WIDTH-1:0]   m_axi_bid,
    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output wire                  m_axi_bready,
    // Read path
    output reg  [ID_WIDTH-1:0]   m_axi_arid,
    output reg  [ADDR_WIDTH-1:0] m_axi_araddr,
    output reg  [7:0]            m_axi_arlen,
    output wire [2:0]            m_axi_arsize,
    output wire [1:0]            m_axi_arburst,
    output wire                  m_axi_arlock,
    output wire [3:0]            m_axi_arcache,
    output wire [2:0]            m_axi_arprot,
    output wire [3:0]            m_axi_arqos,
    output reg                   m_axi_arvalid,
    input  wire                  m_axi_arready,
    input  wire [ID_WIDTH-1:0]   m_axi_rid,
    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output wire                  m_axi_rready
);

// ---- Tie off write path ----
assign m_axi_awid    = {ID_WIDTH{1'b0}};
assign m_axi_awaddr  = {ADDR_WIDTH{1'b0}};
assign m_axi_awlen   = 8'h00;
assign m_axi_awsize  = 3'b010;
assign m_axi_awburst = 2'b01;
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

// ---- Fixed read signals ----
assign m_axi_arsize  = 3'b010;
assign m_axi_arburst = 2'b01;
assign m_axi_arlock  = 1'b0;
assign m_axi_arcache = 4'b0010;
assign m_axi_arprot  = 3'b000;
assign m_axi_arqos   = 4'h0;
assign m_axi_rready  = 1'b1;   // always consume fetched pixels

// =========================================================================
// Pixel clock divider
// =========================================================================
reg [$clog2(CLK_DIV)-1:0] clk_div_cnt;
reg pclk;

always @(posedge clk) begin
    if (rst) begin
        clk_div_cnt <= 0;
        pclk        <= 1'b0;
    end else begin
        if (clk_div_cnt == CLK_DIV/2 - 1) begin
            clk_div_cnt <= 0;
            pclk        <= ~pclk;
        end else begin
            clk_div_cnt <= clk_div_cnt + 1;
        end
    end
end

assign vga_clk_out = pclk;

// =========================================================================
// Horizontal / Vertical counters (run on pixel clock edge)
// =========================================================================
localparam DEF_H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;  // 800
localparam DEF_V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;  // 525

wire [15:0] eff_h_total      = (h_total != 16'd0)      ? h_total      : DEF_H_TOTAL;
wire [15:0] eff_h_active     = (h_active != 16'd0)     ? h_active     : H_ACTIVE;
wire [15:0] eff_v_total      = (v_total != 16'd0)      ? v_total      : DEF_V_TOTAL;
wire [15:0] eff_v_active     = (v_active != 16'd0)     ? v_active     : V_ACTIVE;
wire [15:0] eff_h_sync_start = (h_sync_start != 16'd0) ? h_sync_start : (H_ACTIVE + H_FP);
wire [15:0] eff_h_sync_end   = (h_sync_end != 16'd0)   ? h_sync_end   : (H_ACTIVE + H_FP + H_SYNC);
wire [15:0] eff_v_sync_start = (v_sync_start != 16'd0) ? v_sync_start : (V_ACTIVE + V_FP);
wire [15:0] eff_v_sync_end   = (v_sync_end != 16'd0)   ? v_sync_end   : (V_ACTIVE + V_FP + V_SYNC);

reg [15:0] h_cnt;
reg [15:0] v_cnt;
reg        pclk_prev;

wire pclk_rise = pclk && !pclk_prev;

always @(posedge clk) begin
    if (rst) begin
        h_cnt     <= 16'd0;
        v_cnt     <= 16'd0;
        pclk_prev <= 1'b0;
    end else begin
        pclk_prev <= pclk;
        if (pclk_rise) begin
            if (h_cnt == eff_h_total - 16'd1) begin
                h_cnt <= 16'd0;
                if (v_cnt == eff_v_total - 16'd1)
                    v_cnt <= 16'd0;
                else
                    v_cnt <= v_cnt + 16'd1;
            end else begin
                h_cnt <= h_cnt + 16'd1;
            end
        end
    end
end

// ---- Sync and blanking signals ----
wire h_sync_r = (h_cnt >= eff_h_sync_start) && (h_cnt < eff_h_sync_end);
wire v_sync_r = (v_cnt >= eff_v_sync_start) && (v_cnt < eff_v_sync_end);
wire de       = (h_cnt < eff_h_active) && (v_cnt < eff_v_active);  // display enable

// Polarity: default active-low (pol=0), or active-high if pol=1
assign vga_hsync   = hsync_pol ? h_sync_r : ~h_sync_r;
assign vga_vsync   = vsync_pol ? v_sync_r : ~v_sync_r;
assign vga_blank_n = de;
assign vga_sync_n  = 1'b0;
assign hsync_active = h_sync_r;
assign vsync_active = v_sync_r;

// =========================================================================
// Simple pixel FIFO (16-entry) – AXI read data → display
// =========================================================================
reg [DATA_WIDTH-1:0] pix_fifo [0:15];
reg [4:0]  pf_wr_ptr, pf_rd_ptr;
wire [4:0] pf_count = pf_wr_ptr - pf_rd_ptr;
wire       pf_empty = (pf_count == 0);
wire       pf_full  = (pf_count >= 16);

// Push AXI read data into FIFO
always @(posedge clk) begin
    if (rst) begin
        pf_wr_ptr <= 0;
    end else begin
        if (m_axi_rvalid && !pf_full) begin
            pix_fifo[pf_wr_ptr[3:0]] <= m_axi_rdata;
            pf_wr_ptr                 <= pf_wr_ptr + 1;
        end
    end
end

// Pop FIFO on pixel clock during active display
reg [DATA_WIDTH-1:0] current_pixel;
always @(posedge clk) begin
    if (rst) begin
        pf_rd_ptr     <= 0;
        current_pixel <= 0;
    end else if (pclk_rise && de && !pf_empty) begin
        current_pixel <= pix_fifo[pf_rd_ptr[3:0]];
        pf_rd_ptr     <= pf_rd_ptr + 1;
    end
end

// Pixel data output (XRGB 8-8-8)
assign vga_r = de ? current_pixel[23:16] : 8'h00;
assign vga_g = de ? current_pixel[15: 8] : 8'h00;
assign vga_b = de ? current_pixel[ 7: 0] : 8'h00;

// =========================================================================
// AXI read request engine – prefetch lines ahead of display
// =========================================================================
reg [ADDR_WIDTH-1:0] fetch_addr;
reg [9:0]            fetch_row;
reg                  fetch_active;

localparam BURST_LEN = 8'd15;   // 16-beat bursts (64 bytes per burst)

always @(posedge clk) begin
    if (rst) begin
        m_axi_arvalid <= 1'b0;
        m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
        m_axi_arlen   <= BURST_LEN;
        m_axi_arid    <= {ID_WIDTH{1'b0}};
        fetch_addr    <= {ADDR_WIDTH{1'b0}};
        fetch_row     <= 0;
        fetch_active  <= 1'b0;
    end else begin
        // Start new frame fetch on vsync
        if (v_cnt == 0 && h_cnt == 0 && pclk_rise) begin
            fetch_addr   <= fb_base;
            fetch_row    <= 0;
            fetch_active <= vga_en;
        end

        // Issue burst reads while display is enabled and FIFO has room
        if (fetch_active && !pf_full && !m_axi_arvalid) begin
            m_axi_arvalid <= 1'b1;
            m_axi_araddr  <= fetch_addr;
            m_axi_arlen   <= BURST_LEN;
        end

        if (m_axi_arvalid && m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
            fetch_addr    <= fetch_addr + ((BURST_LEN + 1) * 4);
            if (fetch_addr + ((BURST_LEN + 1) * 4) >= fb_base + (H_ACTIVE * V_ACTIVE * 4))
                fetch_active <= 1'b0;
        end
    end
end

endmodule

`resetall
