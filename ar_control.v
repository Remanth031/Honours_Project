// =============================================================================
// ar_control.v  –  Array Rasterizer Control/Status Slave (AXI4-Lite)
// Address: 0x2000_0000  Size: 4 KB (ADDR_WIDTH=12)
// Access: VeeR CPU only (R/W)
//
// Register Map (word-addressed, 32-bit):
//  0x00  CTRL         [0]=START, [1]=RESET_AR
//  0x04  STATUS       [0]=BUSY, [1]=DONE, [2]=ERROR  (RO)
//  0x08  PRIM_TYPE    [1:0]  0=LINE, 1=TRIANGLE
//  0x0C  PRIM_BASE    Vertex/endpoint base address in data memory
//  0x10  PRIM_COUNT   Number of vertices/endpoints
//  0x14  COLOR        XRGB colour (24-bit pixel value)
//  0x18  FB_BASE      Framebuffer destination base address
//  0x1C  FB_STRIDE    Framebuffer row stride in bytes
//  0x20  IRQ_MASK     [0]=DONE_IE, [1]=ERROR_IE
//  0x24  IRQ_STATUS   [0]=DONE_IRQ, [1]=ERROR_IRQ  (W1C)
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module ar_control #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8
)(
    input  wire                  clk,
    input  wire                  rst,

    // ---- AXI4-Lite Slave Interface ----
    // Write address
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
    // Write data
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [STRB_WIDTH-1:0] s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    // Write response
    output wire [ID_WIDTH-1:0]   s_axi_bid,
    output wire [1:0]            s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,
    // Read address
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
    // Read data
    output wire [ID_WIDTH-1:0]   s_axi_rid,
    output wire [DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output wire                  s_axi_rlast,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready,

    // ---- Sideband to AR engine ----
    output reg        ar_start,        // pulse: start rasterization
    output reg        ar_reset,        // level: reset AR engine
    output reg  [1:0] ar_prim_type,    // 0=line, 1=triangle
    output reg [31:0] ar_prim_base,    // vertex base address
    output reg [31:0] ar_prim_count,   // vertex count
    output reg [23:0] ar_color,        // pixel colour
    output reg [31:0] ar_fb_base,      // framebuffer base address
    output reg [31:0] ar_fb_stride,    // framebuffer stride (bytes)
    input  wire       ar_busy,         // AR engine busy
    input  wire       ar_done,         // AR engine done (pulse)
    input  wire       ar_error,        // AR engine error flag

    // ---- Interrupt to CPU ----
    output wire       irq
);

// -------------------------------------------------------------------------
// Internal registers
// -------------------------------------------------------------------------
reg [31:0] reg_ctrl;        // 0x00
// reg_status assembled from inputs
reg [31:0] reg_prim_type;   // 0x08
reg [31:0] reg_prim_base;   // 0x0C
reg [31:0] reg_prim_count;  // 0x10
reg [31:0] reg_color;       // 0x14
reg [31:0] reg_fb_base;     // 0x18
reg [31:0] reg_fb_stride;   // 0x1C
reg [31:0] reg_irq_mask;    // 0x20
reg [31:0] reg_irq_status;  // 0x24 (W1C)

// Sideband outputs
always @(*) begin
    ar_start      = reg_ctrl[0];
    ar_reset      = reg_ctrl[1];
    ar_prim_type  = reg_prim_type[1:0];
    ar_prim_base  = reg_prim_base;
    ar_prim_count = reg_prim_count;
    ar_color      = reg_color[23:0];
    ar_fb_base    = reg_fb_base;
    ar_fb_stride  = reg_fb_stride;
end

// IRQ status latching (done/error are level inputs; latch on rising edge)
reg ar_done_prev, ar_error_prev;
always @(posedge clk) begin
    if (rst) begin
        reg_irq_status <= 32'd0;
        ar_done_prev   <= 1'b0;
        ar_error_prev  <= 1'b0;
    end else begin
        ar_done_prev  <= ar_done;
        ar_error_prev <= ar_error;
        if (ar_done  && !ar_done_prev)  reg_irq_status[0] <= 1'b1;
        if (ar_error && !ar_error_prev) reg_irq_status[1] <= 1'b1;
    end
end

assign irq = |(reg_irq_status & reg_irq_mask[1:0]);

// ---- Simple AXI4-Lite write path ----
reg aw_latch_v; reg [ADDR_WIDTH-1:0] aw_latch_addr; reg [ID_WIDTH-1:0] aw_latch_id;
reg w_latch_v;  reg [DATA_WIDTH-1:0] w_latch_data;  reg [STRB_WIDTH-1:0] w_latch_strb;
reg b_valid_r;  reg [ID_WIDTH-1:0]   b_id_r;

assign s_axi_awready = !aw_latch_v;
assign s_axi_wready  = !w_latch_v;
assign s_axi_bvalid  = b_valid_r;
assign s_axi_bid     = b_id_r;
assign s_axi_bresp   = 2'b00;

always @(posedge clk) begin
    if (rst) begin
        aw_latch_v <= 0; w_latch_v <= 0; b_valid_r <= 0;
        reg_ctrl <= 0; reg_prim_type <= 0; reg_prim_base <= 0;
        reg_prim_count <= 0; reg_color <= 0; reg_fb_base <= 0;
        reg_fb_stride <= 0; reg_irq_mask <= 0;
    end else begin
        // Capture AW
        if (!aw_latch_v && s_axi_awvalid) begin
            aw_latch_v    <= 1;
            aw_latch_addr <= s_axi_awaddr;
            aw_latch_id   <= s_axi_awid;
        end
        // Capture W
        if (!w_latch_v && s_axi_wvalid) begin
            w_latch_v    <= 1;
            w_latch_data <= s_axi_wdata;
            w_latch_strb <= s_axi_wstrb;
        end
        // Write register when both captured
        if (aw_latch_v && w_latch_v) begin
            case (aw_latch_addr[5:2])
                4'h0: reg_ctrl        <= w_latch_data;
                4'h2: reg_prim_type   <= w_latch_data;
                4'h3: reg_prim_base   <= w_latch_data;
                4'h4: reg_prim_count  <= w_latch_data;
                4'h5: reg_color       <= w_latch_data;
                4'h6: reg_fb_base     <= w_latch_data;
                4'h7: reg_fb_stride   <= w_latch_data;
                4'h8: reg_irq_mask    <= w_latch_data;
                4'h9: reg_irq_status  <= reg_irq_status & ~w_latch_data; // W1C
                default: ;
            endcase
            // auto-clear START bit
            if (aw_latch_addr[5:2] == 4'h0) reg_ctrl[0] <= 1'b0;
            aw_latch_v <= 0; w_latch_v <= 0;
            b_valid_r  <= 1; b_id_r <= aw_latch_id;
        end
        if (b_valid_r && s_axi_bready) b_valid_r <= 0;
    end
end

// ---- Simple AXI4-Lite read path ----
reg ar_active_r;
reg [ADDR_WIDTH-1:0] ar_addr_r;
reg [ID_WIDTH-1:0]   ar_id_r;
reg [DATA_WIDTH-1:0] ar_rdata_r;

assign s_axi_arready = !ar_active_r;
assign s_axi_rvalid  = ar_active_r;
assign s_axi_rid     = ar_id_r;
assign s_axi_rdata   = ar_rdata_r;
assign s_axi_rresp   = 2'b00;
assign s_axi_rlast   = ar_active_r;

always @(posedge clk) begin
    if (rst) begin
        ar_active_r <= 0;
    end else begin
        if (!ar_active_r && s_axi_arvalid) begin
            ar_active_r <= 1;
            ar_id_r     <= s_axi_arid;
            case (s_axi_araddr[5:2])
                4'h0: ar_rdata_r <= reg_ctrl;
                4'h1: ar_rdata_r <= {29'd0, ar_error, ar_done, ar_busy};
                4'h2: ar_rdata_r <= reg_prim_type;
                4'h3: ar_rdata_r <= reg_prim_base;
                4'h4: ar_rdata_r <= reg_prim_count;
                4'h5: ar_rdata_r <= reg_color;
                4'h6: ar_rdata_r <= reg_fb_base;
                4'h7: ar_rdata_r <= reg_fb_stride;
                4'h8: ar_rdata_r <= reg_irq_mask;
                4'h9: ar_rdata_r <= reg_irq_status;
                default: ar_rdata_r <= 32'hDEAD_BEEF;
            endcase
        end
        if (ar_active_r && s_axi_rready) ar_active_r <= 0;
    end
end

endmodule

`resetall
