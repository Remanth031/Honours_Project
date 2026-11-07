// =============================================================================
// framebuffer.v  –  Framebuffer Slave (AXI4)
// Address: 0x1000_0000  Size: 16 MB (ADDR_WIDTH=24)
// Access: VeeR CPU (R/W), AR Write (W only), VGA Controller (R only)
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module framebuffer #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8,
    // 640x480 @32bpp = 1,228,800 words; round to 2 M for margin
    parameter MEM_DEPTH  = 2*1024*1024
)(
    input  wire                  clk,
    input  wire                  rst,

    // ---- AXI4 Slave Interface ----
    // Write address channel
    input  wire [ID_WIDTH-1:0]   s_axi_awid,
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [7:0]            s_axi_awlen,
    input  wire [2:0]            s_axi_awsize,
    input  wire [1:0]            s_axi_awburst,
    input  wire                  s_axi_awlock,
    input  wire [3:0]            s_axi_awcache,
    input  wire [2:0]            s_axi_awprot,
    input  wire [3:0]            s_axi_awqos,
    input  wire [3:0]            s_axi_awregion,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    // Write data channel
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [STRB_WIDTH-1:0] s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    // Write response channel
    output wire [ID_WIDTH-1:0]   s_axi_bid,
    output wire [1:0]            s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,
    // Read address channel
    input  wire [ID_WIDTH-1:0]   s_axi_arid,
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [7:0]            s_axi_arlen,
    input  wire [2:0]            s_axi_arsize,
    input  wire [1:0]            s_axi_arburst,
    input  wire                  s_axi_arlock,
    input  wire [3:0]            s_axi_arcache,
    input  wire [2:0]            s_axi_arprot,
    input  wire [3:0]            s_axi_arqos,
    input  wire [3:0]            s_axi_arregion,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    // Read data channel
    output wire [ID_WIDTH-1:0]   s_axi_rid,
    output wire [DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output wire                  s_axi_rlast,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready
);

// -------------------------------------------------------------------------
// Pixel BRAM (stub – behavioural model; replace with FPGA BRAM primitive)
// Each word = one 32-bit RGBA/XRGB pixel
// -------------------------------------------------------------------------
reg [DATA_WIDTH-1:0] fb_mem [0:MEM_DEPTH-1];

// ---------- Write path ----------
reg                  aw_active;
reg [ADDR_WIDTH-1:0] aw_addr_r;
reg [ID_WIDTH-1:0]   aw_id_r;
reg [7:0]            aw_len_r;
reg [7:0]            aw_beat;

assign s_axi_awready = !aw_active;

always @(posedge clk) begin
    if (rst) begin
        aw_active <= 1'b0;
        aw_beat   <= 8'd0;
    end else begin
        if (!aw_active && s_axi_awvalid) begin
            aw_active <= 1'b1;
            aw_addr_r <= s_axi_awaddr;
            aw_id_r   <= s_axi_awid;
            aw_len_r  <= s_axi_awlen;
            aw_beat   <= 8'd0;
        end
        if (aw_active && s_axi_wvalid) begin
            if (s_axi_wstrb[0]) fb_mem[aw_addr_r[ADDR_WIDTH-1:2] + aw_beat][ 7: 0] <= s_axi_wdata[ 7: 0];
            if (s_axi_wstrb[1]) fb_mem[aw_addr_r[ADDR_WIDTH-1:2] + aw_beat][15: 8] <= s_axi_wdata[15: 8];
            if (s_axi_wstrb[2]) fb_mem[aw_addr_r[ADDR_WIDTH-1:2] + aw_beat][23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) fb_mem[aw_addr_r[ADDR_WIDTH-1:2] + aw_beat][31:24] <= s_axi_wdata[31:24];
            if (s_axi_wlast)
                aw_active <= 1'b0;
            else
                aw_beat <= aw_beat + 1;
        end
    end
end

assign s_axi_wready = aw_active;

// Write response
reg b_valid;
reg [ID_WIDTH-1:0] b_id;
always @(posedge clk) begin
    if (rst) begin
        b_valid <= 1'b0;
    end else begin
        if (aw_active && s_axi_wvalid && s_axi_wlast)
            b_valid <= 1'b1;
        else if (b_valid && s_axi_bready)
            b_valid <= 1'b0;
        if (aw_active && s_axi_wvalid && s_axi_wlast)
            b_id <= aw_id_r;
    end
end
assign s_axi_bvalid = b_valid;
assign s_axi_bid    = b_id;
assign s_axi_bresp  = 2'b00;

// ---------- Read path ----------
reg                  ar_active;
reg [ADDR_WIDTH-1:0] ar_addr_r;
reg [ID_WIDTH-1:0]   ar_id_r;
reg [7:0]            ar_len_r;
reg [7:0]            ar_beat;

assign s_axi_arready = !ar_active;

always @(posedge clk) begin
    if (rst) begin
        ar_active <= 1'b0;
        ar_beat   <= 8'd0;
    end else begin
        if (!ar_active && s_axi_arvalid) begin
            ar_active <= 1'b1;
            ar_addr_r <= s_axi_araddr;
            ar_id_r   <= s_axi_arid;
            ar_len_r  <= s_axi_arlen;
            ar_beat   <= 8'd0;
        end
        if (ar_active && s_axi_rready) begin
            if (ar_beat == ar_len_r)
                ar_active <= 1'b0;
            else
                ar_beat <= ar_beat + 1;
        end
    end
end

assign s_axi_rvalid = ar_active;
assign s_axi_rid    = ar_id_r;
assign s_axi_rdata  = fb_mem[ar_addr_r[ADDR_WIDTH-1:2] + ar_beat];
assign s_axi_rresp  = 2'b00;
assign s_axi_rlast  = ar_active && (ar_beat == ar_len_r);

endmodule

`resetall
