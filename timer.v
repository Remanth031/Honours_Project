// =============================================================================
// timer.v  –  Dual-Channel Countdown Timer Slave (AXI4-Lite)
// Address: 0x2006_0000  Size: 4 KB (12-bit slave window)
// Access: VeeR CPU only (R/W)
//
// Register Map (word-addressed, 32-bit):
//  Channel A (base 0x00):
//   0x00  CTRL_A      [0]=EN, [1]=AUTO_RELOAD, [2]=ONE_SHOT  (R/W)
//   0x04  LOAD_A      32-bit load/reload value                (R/W)
//   0x08  COUNTER_A   current counter value (counts down)     (RO)
//   0x0C  IRQ_EN_A    [0]=MATCH_IE                            (R/W)
//   0x10  IRQ_STAT_A  [0]=MATCH_IRQ                          (R/W, W1C)
//  Channel B (base 0x20):
//   0x20  CTRL_B      [0]=EN, [1]=AUTO_RELOAD, [2]=ONE_SHOT  (R/W)
//   0x24  LOAD_B      32-bit load/reload value                (R/W)
//   0x28  COUNTER_B   current counter value (counts down)     (RO)
//   0x2C  IRQ_EN_B    [0]=MATCH_IE                            (R/W)
//   0x30  IRQ_STAT_B  [0]=MATCH_IRQ                          (R/W, W1C)
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module timer #(
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

    // ---- Sideband interrupt outputs ----
    output wire  timer_irq_a,
    output wire  timer_irq_b
);

// =========================================================================
// Internal registers – Channel A
// =========================================================================
reg [31:0] reg_ctrl_a;      // 0x00  [0]=EN [1]=AUTO_RELOAD [2]=ONE_SHOT
reg [31:0] reg_load_a;      // 0x04
reg [31:0] reg_counter_a;   // 0x08  (RO, driven by timer logic)
reg [31:0] reg_irq_en_a;    // 0x0C  [0]=MATCH_IE
reg [31:0] reg_irq_stat_a;  // 0x10  [0]=MATCH_IRQ (W1C)

// =========================================================================
// Internal registers – Channel B
// =========================================================================
reg [31:0] reg_ctrl_b;      // 0x20
reg [31:0] reg_load_b;      // 0x24
reg [31:0] reg_counter_b;   // 0x28  (RO)
reg [31:0] reg_irq_en_b;    // 0x2C
reg [31:0] reg_irq_stat_b;  // 0x30  (W1C)

// =========================================================================
// IRQ outputs
// =========================================================================
assign timer_irq_a = reg_irq_stat_a[0] & reg_irq_en_a[0];
assign timer_irq_b = reg_irq_stat_b[0] & reg_irq_en_b[0];

// =========================================================================
// AXI4-Lite Write path – latch/handshake state
// =========================================================================
reg                  aw_latch_v;
reg [ADDR_WIDTH-1:0] aw_latch_addr;
reg [ID_WIDTH-1:0]   aw_latch_id;
reg                  w_latch_v;
reg [DATA_WIDTH-1:0] w_latch_data;
reg [STRB_WIDTH-1:0] w_latch_strb;
reg                  b_valid_r;
reg [ID_WIDTH-1:0]   b_id_r;

assign s_axi_awready = !aw_latch_v;
assign s_axi_wready  = !w_latch_v;
assign s_axi_bvalid  = b_valid_r;
assign s_axi_bid     = b_id_r;
assign s_axi_bresp   = 2'b00;

// Decode: AXI write fires on this cycle
wire do_write = aw_latch_v && w_latch_v;

// ---- AW / W / B handshake (address+data latches, B-channel) ----
always @(posedge clk) begin
    if (rst) begin
        aw_latch_v    <= 1'b0;
        aw_latch_addr <= {ADDR_WIDTH{1'b0}};
        aw_latch_id   <= {ID_WIDTH{1'b0}};
        w_latch_v     <= 1'b0;
        w_latch_data  <= {DATA_WIDTH{1'b0}};
        w_latch_strb  <= {STRB_WIDTH{1'b0}};
        b_valid_r     <= 1'b0;
        b_id_r        <= {ID_WIDTH{1'b0}};
    end else begin
        // Capture AW
        if (!aw_latch_v && s_axi_awvalid) begin
            aw_latch_v    <= 1'b1;
            aw_latch_addr <= s_axi_awaddr;
            aw_latch_id   <= s_axi_awid;
        end
        // Capture W
        if (!w_latch_v && s_axi_wvalid) begin
            w_latch_v    <= 1'b1;
            w_latch_data <= s_axi_wdata;
            w_latch_strb <= s_axi_wstrb;
        end
        // Release both latches and send B when write executes
        if (do_write) begin
            aw_latch_v <= 1'b0;
            w_latch_v  <= 1'b0;
            b_valid_r  <= 1'b1;
            b_id_r     <= aw_latch_id;
        end
        // Retire B-channel
        if (b_valid_r && s_axi_bready) b_valid_r <= 1'b0;
    end
end

// =========================================================================
// Channel A register file + timer FSM  (single always block avoids
// multi-driver: AXI write path and timer FSM both modify reg_ctrl_a,
// reg_counter_a, reg_irq_stat_a)
// =========================================================================
always @(posedge clk) begin
    if (rst) begin
        reg_ctrl_a     <= 32'd0;
        reg_load_a     <= 32'd0;
        reg_counter_a  <= 32'd0;
        reg_irq_en_a   <= 32'd0;
        reg_irq_stat_a <= 32'd0;
    end else begin
        // ---- Timer FSM (runs every cycle when EN=1) ----
        if (reg_ctrl_a[0]) begin                      // EN=1
            if (reg_counter_a == 32'd0) begin
                // Counter hit zero → fire IRQ sticky bit
                reg_irq_stat_a[0] <= 1'b1;
                if (reg_ctrl_a[2]) begin               // ONE_SHOT: stop and pre-load
                    reg_ctrl_a[0] <= 1'b0;
                    reg_counter_a <= reg_load_a;
                end else if (reg_ctrl_a[1]) begin      // AUTO_RELOAD: restart
                    reg_counter_a <= reg_load_a;
                end else begin                         // plain single-run: freeze
                    reg_ctrl_a[0] <= 1'b0;
                end
            end else begin
                reg_counter_a <= reg_counter_a - 32'd1;
            end
        end

        // ---- AXI write (takes priority over timer FSM on same cycle) ----
        if (do_write) begin
            case (aw_latch_addr[5:2])
                4'h0: begin  // CTRL_A
                    if (w_latch_strb[0]) reg_ctrl_a[ 7: 0] <= w_latch_data[ 7: 0];
                    if (w_latch_strb[1]) reg_ctrl_a[15: 8] <= w_latch_data[15: 8];
                    if (w_latch_strb[2]) reg_ctrl_a[23:16] <= w_latch_data[23:16];
                    if (w_latch_strb[3]) reg_ctrl_a[31:24] <= w_latch_data[31:24];
                end
                4'h1: begin  // LOAD_A
                    if (w_latch_strb[0]) reg_load_a[ 7: 0] <= w_latch_data[ 7: 0];
                    if (w_latch_strb[1]) reg_load_a[15: 8] <= w_latch_data[15: 8];
                    if (w_latch_strb[2]) reg_load_a[23:16] <= w_latch_data[23:16];
                    if (w_latch_strb[3]) reg_load_a[31:24] <= w_latch_data[31:24];
                end
                // 4'h2 COUNTER_A → RO, ignore
                4'h3: begin  // IRQ_EN_A
                    if (w_latch_strb[0]) reg_irq_en_a[ 7: 0] <= w_latch_data[ 7: 0];
                    if (w_latch_strb[1]) reg_irq_en_a[15: 8] <= w_latch_data[15: 8];
                    if (w_latch_strb[2]) reg_irq_en_a[23:16] <= w_latch_data[23:16];
                    if (w_latch_strb[3]) reg_irq_en_a[31:24] <= w_latch_data[31:24];
                end
                4'h4: begin  // IRQ_STAT_A (W1C)
                    if (w_latch_strb[0]) reg_irq_stat_a[ 7: 0] <= reg_irq_stat_a[ 7: 0] & ~w_latch_data[ 7: 0];
                    if (w_latch_strb[1]) reg_irq_stat_a[15: 8] <= reg_irq_stat_a[15: 8] & ~w_latch_data[15: 8];
                    if (w_latch_strb[2]) reg_irq_stat_a[23:16] <= reg_irq_stat_a[23:16] & ~w_latch_data[23:16];
                    if (w_latch_strb[3]) reg_irq_stat_a[31:24] <= reg_irq_stat_a[31:24] & ~w_latch_data[31:24];
                end
                default: ; // not a channel-A address, ignore
            endcase
        end
    end
end

// =========================================================================
// Channel B register file + timer FSM
// =========================================================================
always @(posedge clk) begin
    if (rst) begin
        reg_ctrl_b     <= 32'd0;
        reg_load_b     <= 32'd0;
        reg_counter_b  <= 32'd0;
        reg_irq_en_b   <= 32'd0;
        reg_irq_stat_b <= 32'd0;
    end else begin
        // ---- Timer FSM ----
        if (reg_ctrl_b[0]) begin
            if (reg_counter_b == 32'd0) begin
                reg_irq_stat_b[0] <= 1'b1;
                if (reg_ctrl_b[2]) begin
                    reg_ctrl_b[0] <= 1'b0;
                    reg_counter_b <= reg_load_b;
                end else if (reg_ctrl_b[1]) begin
                    reg_counter_b <= reg_load_b;
                end else begin
                    reg_ctrl_b[0] <= 1'b0;
                end
            end else begin
                reg_counter_b <= reg_counter_b - 32'd1;
            end
        end

        // ---- AXI write ----
        if (do_write) begin
            case (aw_latch_addr[5:2])
                4'h8: begin  // CTRL_B
                    if (w_latch_strb[0]) reg_ctrl_b[ 7: 0] <= w_latch_data[ 7: 0];
                    if (w_latch_strb[1]) reg_ctrl_b[15: 8] <= w_latch_data[15: 8];
                    if (w_latch_strb[2]) reg_ctrl_b[23:16] <= w_latch_data[23:16];
                    if (w_latch_strb[3]) reg_ctrl_b[31:24] <= w_latch_data[31:24];
                end
                4'h9: begin  // LOAD_B
                    if (w_latch_strb[0]) reg_load_b[ 7: 0] <= w_latch_data[ 7: 0];
                    if (w_latch_strb[1]) reg_load_b[15: 8] <= w_latch_data[15: 8];
                    if (w_latch_strb[2]) reg_load_b[23:16] <= w_latch_data[23:16];
                    if (w_latch_strb[3]) reg_load_b[31:24] <= w_latch_data[31:24];
                end
                // 4'hA COUNTER_B → RO, ignore
                4'hB: begin  // IRQ_EN_B
                    if (w_latch_strb[0]) reg_irq_en_b[ 7: 0] <= w_latch_data[ 7: 0];
                    if (w_latch_strb[1]) reg_irq_en_b[15: 8] <= w_latch_data[15: 8];
                    if (w_latch_strb[2]) reg_irq_en_b[23:16] <= w_latch_data[23:16];
                    if (w_latch_strb[3]) reg_irq_en_b[31:24] <= w_latch_data[31:24];
                end
                4'hC: begin  // IRQ_STAT_B (W1C)
                    if (w_latch_strb[0]) reg_irq_stat_b[ 7: 0] <= reg_irq_stat_b[ 7: 0] & ~w_latch_data[ 7: 0];
                    if (w_latch_strb[1]) reg_irq_stat_b[15: 8] <= reg_irq_stat_b[15: 8] & ~w_latch_data[15: 8];
                    if (w_latch_strb[2]) reg_irq_stat_b[23:16] <= reg_irq_stat_b[23:16] & ~w_latch_data[23:16];
                    if (w_latch_strb[3]) reg_irq_stat_b[31:24] <= reg_irq_stat_b[31:24] & ~w_latch_data[31:24];
                end
                default: ;
            endcase
        end
    end
end

// =========================================================================
// AXI4-Lite Read path
// =========================================================================
reg                  ar_active_r;
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
        ar_active_r <= 1'b0;
        ar_id_r     <= {ID_WIDTH{1'b0}};
        ar_rdata_r  <= {DATA_WIDTH{1'b0}};
    end else begin
        if (!ar_active_r && s_axi_arvalid) begin
            ar_active_r <= 1'b1;
            ar_id_r     <= s_axi_arid;
            case (s_axi_araddr[5:2])
                // ---- Channel A ----
                4'h0: ar_rdata_r <= reg_ctrl_a;
                4'h1: ar_rdata_r <= reg_load_a;
                4'h2: ar_rdata_r <= reg_counter_a;
                4'h3: ar_rdata_r <= reg_irq_en_a;
                4'h4: ar_rdata_r <= reg_irq_stat_a;
                // ---- Channel B ----
                4'h8: ar_rdata_r <= reg_ctrl_b;
                4'h9: ar_rdata_r <= reg_load_b;
                4'hA: ar_rdata_r <= reg_counter_b;
                4'hB: ar_rdata_r <= reg_irq_en_b;
                4'hC: ar_rdata_r <= reg_irq_stat_b;
                default: ar_rdata_r <= 32'hDEAD_BEEF;
            endcase
        end
        if (ar_active_r && s_axi_rready) ar_active_r <= 1'b0;
    end
end

endmodule

`resetall
