// =============================================================================
// hpm.v  –  Hardware Performance Monitor Slave (AXI4-Lite)
// Address: 0x2001_0000  Size: 4 KB (ADDR_WIDTH=12)
// Access: VeeR CPU only (R/W)
//
// Register Map (word-addressed):
//  0x00  CTRL        [0]=ENABLE, [1]=CLEAR
//  0x04  CPU_CYCLES  CPU cycle counter (RO)
//  0x08  MEM_READS   AXI read-transaction counter (RO)
//  0x0C  MEM_WRITES  AXI write-transaction counter (RO)
//  0x10  PIXELS_OUT  Pixels produced by AR engine (RO)
//  0x14  AR_ACTIVE   AR engine active cycles (RO)
//  0x18  SETUP_OVH   Command-setup overhead cycles (RO)
//  0x1C  IRQ_OVH     Interrupt-handling overhead cycles (RO)
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module hpm #(
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

    // ---- Sideband event inputs ----
    input  wire       ev_mem_read,     // pulse: AXI read transaction
    input  wire       ev_mem_write,    // pulse: AXI write transaction
    input  wire       ev_pixel_out,    // pulse: pixel written by AR
    input  wire       ev_ar_active,    // level: AR engine running
    input  wire       ev_setup,        // level: CPU in setup overhead
    input  wire       ev_irq_handling  // level: CPU in IRQ handler
);

// ---- Counter registers ----
reg [31:0] cnt_cpu_cycles;
reg [31:0] cnt_mem_reads;
reg [31:0] cnt_mem_writes;
reg [31:0] cnt_pixels_out;
reg [31:0] cnt_ar_active;
reg [31:0] cnt_setup_ovh;
reg [31:0] cnt_irq_ovh;
reg        hpm_enable;

// ---- AXI4-Lite Write (CTRL register only writable) ----
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
        cnt_cpu_cycles <= 0; cnt_mem_reads  <= 0; cnt_mem_writes <= 0;
        cnt_pixels_out <= 0; cnt_ar_active  <= 0; cnt_setup_ovh  <= 0;
        cnt_irq_ovh    <= 0; hpm_enable     <= 0;
        aw_latch_v     <= 0; w_latch_v      <= 0; bvalid_r        <= 0;
        bid_r          <= 0; aw_addr_l      <= 0; aw_id_l         <= 0;
        w_data_l       <= 0;
    end else begin
        if (hpm_enable) begin
            cnt_cpu_cycles <= cnt_cpu_cycles + 1;
            if (ev_mem_read)    cnt_mem_reads  <= cnt_mem_reads  + 1;
            if (ev_mem_write)   cnt_mem_writes <= cnt_mem_writes + 1;
            if (ev_pixel_out)   cnt_pixels_out <= cnt_pixels_out + 1;
            if (ev_ar_active)   cnt_ar_active  <= cnt_ar_active  + 1;
            if (ev_setup)       cnt_setup_ovh  <= cnt_setup_ovh  + 1;
            if (ev_irq_handling)cnt_irq_ovh    <= cnt_irq_ovh    + 1;
        end

        if (!aw_latch_v && s_axi_awvalid) begin aw_latch_v <= 1; aw_addr_l <= s_axi_awaddr; aw_id_l <= s_axi_awid; end
        if (!w_latch_v  && s_axi_wvalid)  begin w_latch_v  <= 1; w_data_l  <= s_axi_wdata; end
        if (aw_latch_v && w_latch_v) begin
            if (aw_addr_l[4:2] == 3'h0) begin
                hpm_enable <= w_data_l[0];
                if (w_data_l[1]) begin  // CLEAR
                    cnt_cpu_cycles <= 0; cnt_mem_reads  <= 0; cnt_mem_writes <= 0;
                    cnt_pixels_out <= 0; cnt_ar_active  <= 0; cnt_setup_ovh  <= 0;
                    cnt_irq_ovh    <= 0;
                end
            end
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
                3'h0: ar_rdata_r <= {31'd0, hpm_enable};
                3'h1: ar_rdata_r <= cnt_cpu_cycles;
                3'h2: ar_rdata_r <= cnt_mem_reads;
                3'h3: ar_rdata_r <= cnt_mem_writes;
                3'h4: ar_rdata_r <= cnt_pixels_out;
                3'h5: ar_rdata_r <= cnt_ar_active;
                3'h6: ar_rdata_r <= cnt_setup_ovh;
                3'h7: ar_rdata_r <= cnt_irq_ovh;
                default: ar_rdata_r <= 32'hDEAD_BEEF;
            endcase
        end
        if (ar_act_r && s_axi_rready) ar_act_r <= 0;
    end
end

endmodule

`resetall
