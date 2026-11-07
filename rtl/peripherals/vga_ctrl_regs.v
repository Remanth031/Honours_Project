// =============================================================================
// vga_ctrl_regs.v  –  VGA Controller Configuration Registers (AXI4-Lite slave)
// Address: 0x2002_0000  Size: 4 KB (ADDR_WIDTH=12)
// Access: VeeR CPU only (R/W)
//
// Register Map:
//  0x00  CTRL         [0]=VGA_EN, [1]=VSYNC_POL, [2]=HSYNC_POL
//  0x04  H_PARAMS     [15:0]=H_TOTAL, [31:16]=H_ACTIVE
//  0x08  V_PARAMS     [15:0]=V_TOTAL, [31:16]=V_ACTIVE
//  0x0C  H_SYNC       [15:0]=H_SYNC_START, [31:16]=H_SYNC_END
//  0x10  V_SYNC       [15:0]=V_SYNC_START, [31:16]=V_SYNC_END
//  0x14  FB_BASE      Framebuffer base address (read by VGA engine)
//  0x18  FB_STRIDE    Row stride in bytes
//  0x1C  STATUS       [0]=VSYNC_ACTIVE, [1]=HSYNC_ACTIVE  (RO)
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module vga_ctrl_regs #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8
)(
    input  wire                  clk,
    input  wire                  rst,

    // ---- AXI4-Lite Slave Interface ----
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
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [STRB_WIDTH-1:0] s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    output wire [ID_WIDTH-1:0]   s_axi_bid,
    output wire [1:0]            s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,
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
    output wire [ID_WIDTH-1:0]   s_axi_rid,
    output wire [DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output wire                  s_axi_rlast,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready,

    // ---- Sideband to/from VGA engine ----
    output wire        vga_en,
    output wire        vsync_pol,
    output wire        hsync_pol,
    output wire [15:0] h_total,
    output wire [15:0] h_active,
    output wire [15:0] v_total,
    output wire [15:0] v_active,
    output wire [15:0] h_sync_start,
    output wire [15:0] h_sync_end,
    output wire [15:0] v_sync_start,
    output wire [15:0] v_sync_end,
    output wire [31:0] vga_fb_base,
    output wire [31:0] vga_fb_stride,
    input  wire        vsync_active,
    input  wire        hsync_active
);

// ---- Registers ----
reg [31:0] reg_ctrl;        // 0x00
reg [31:0] reg_h_params;    // 0x04
reg [31:0] reg_v_params;    // 0x08
reg [31:0] reg_h_sync;      // 0x0C
reg [31:0] reg_v_sync;      // 0x10
reg [31:0] reg_fb_base;     // 0x14
reg [31:0] reg_fb_stride;   // 0x18
// 0x1C = STATUS (read-only from inputs)

// Sideband outputs
assign vga_en       = reg_ctrl[0];
assign vsync_pol    = reg_ctrl[1];
assign hsync_pol    = reg_ctrl[2];
assign h_total      = reg_h_params[15:0];
assign h_active     = reg_h_params[31:16];
assign v_total      = reg_v_params[15:0];
assign v_active     = reg_v_params[31:16];
assign h_sync_start = reg_h_sync[15:0];
assign h_sync_end   = reg_h_sync[31:16];
assign v_sync_start = reg_v_sync[15:0];
assign v_sync_end   = reg_v_sync[31:16];
assign vga_fb_base  = reg_fb_base;
assign vga_fb_stride= reg_fb_stride;

// ---- AXI4-Lite Write ----
reg aw_latch_v; reg [ADDR_WIDTH-1:0] aw_addr_l; reg [ID_WIDTH-1:0] aw_id_l;
reg w_latch_v;  reg [DATA_WIDTH-1:0] w_data_l;
reg bvalid_r;   reg [ID_WIDTH-1:0]   bid_r;

assign s_axi_awready = !aw_latch_v;
assign s_axi_wready  = !w_latch_v;
assign s_axi_bvalid  = bvalid_r;
assign s_axi_bid     = bid_r;
assign s_axi_bresp   = 2'b00;

always @(posedge clk) begin
    if (rst) begin
        aw_latch_v <= 0; w_latch_v <= 0; bvalid_r <= 0;
        reg_ctrl <= 0; reg_h_params <= 32'h0280_0320; // 640 active, 800 total (default 640x480)
        reg_v_params <= 32'h01E0_020D;                 // 480 active, 525 total
        reg_h_sync   <= 32'h0060_0010;                 // sync 16–112
        reg_v_sync   <= 32'h0002_000A;                 // sync 10–12
        reg_fb_base  <= 32'h1000_0000;
        reg_fb_stride<= 32'd2560;                      // 640*4 bytes
    end else begin
        if (!aw_latch_v && s_axi_awvalid) begin aw_latch_v <= 1; aw_addr_l <= s_axi_awaddr; aw_id_l <= s_axi_awid; end
        if (!w_latch_v  && s_axi_wvalid)  begin w_latch_v  <= 1; w_data_l  <= s_axi_wdata; end
        if (aw_latch_v && w_latch_v) begin
            case (aw_addr_l[4:2])
                3'h0: reg_ctrl      <= w_data_l;
                3'h1: reg_h_params  <= w_data_l;
                3'h2: reg_v_params  <= w_data_l;
                3'h3: reg_h_sync    <= w_data_l;
                3'h4: reg_v_sync    <= w_data_l;
                3'h5: reg_fb_base   <= w_data_l;
                3'h6: reg_fb_stride <= w_data_l;
                default: ;
            endcase
            aw_latch_v <= 0; w_latch_v <= 0; bvalid_r <= 1; bid_r <= aw_id_l;
        end
        if (bvalid_r && s_axi_bready) bvalid_r <= 0;
    end
end

// ---- AXI4-Lite Read ----
reg ar_act_r;
reg [ID_WIDTH-1:0]   ar_id_r;
reg [DATA_WIDTH-1:0] ar_rdata_r;

assign s_axi_arready = !ar_act_r;
assign s_axi_rvalid  = ar_act_r;
assign s_axi_rid     = ar_id_r;
assign s_axi_rdata   = ar_rdata_r;
assign s_axi_rresp   = 2'b00;
assign s_axi_rlast   = ar_act_r;

always @(posedge clk) begin
    if (rst) begin
        ar_act_r <= 0;
    end else begin
        if (!ar_act_r && s_axi_arvalid) begin
            ar_act_r <= 1; ar_id_r <= s_axi_arid;
            case (s_axi_araddr[4:2])
                3'h0: ar_rdata_r <= reg_ctrl;
                3'h1: ar_rdata_r <= reg_h_params;
                3'h2: ar_rdata_r <= reg_v_params;
                3'h3: ar_rdata_r <= reg_h_sync;
                3'h4: ar_rdata_r <= reg_v_sync;
                3'h5: ar_rdata_r <= reg_fb_base;
                3'h6: ar_rdata_r <= reg_fb_stride;
                3'h7: ar_rdata_r <= {30'd0, vsync_active, hsync_active};
                default: ar_rdata_r <= 32'hDEAD_BEEF;
            endcase
        end
        if (ar_act_r && s_axi_rready) ar_act_r <= 0;
    end
end

endmodule

`resetall
