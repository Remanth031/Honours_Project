// =============================================================================
// gpio.v  –  General-Purpose I/O Slave (AXI4-Lite)
// Address: 0x2004_0000  Size: 4 KB (12-bit slave window)
// Access: VeeR CPU (R/W)
//
// Register Map (word-addressed, 32-bit):
//  0x00  DATA_OUT   [GPIO_WIDTH-1:0]  R/W  — drives gpio_out port
//  0x04  DATA_IN    [GPIO_WIDTH-1:0]  RO   — samples gpio_in port
//  0x08  DIR        [GPIO_WIDTH-1:0]  R/W  — 1=output, 0=input
//  0x0C  IRQ_EN     [GPIO_WIDTH-1:0]  R/W  — per-bit rising-edge IRQ enable
//  0x10  IRQ_STAT   [GPIO_WIDTH-1:0]  R/W  — W1C sticky rising-edge flags
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module gpio #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8,
    parameter GPIO_WIDTH = 32
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

    // ---- GPIO Sideband Ports ----
    output reg  [GPIO_WIDTH-1:0] gpio_out,   // driven by DATA_OUT register
    input  wire [GPIO_WIDTH-1:0] gpio_in,    // sampled into DATA_IN (read-only)
    output wire                  gpio_irq    // |(IRQ_STAT & IRQ_EN)
);

// -------------------------------------------------------------------------
// Internal registers
// -------------------------------------------------------------------------
reg [GPIO_WIDTH-1:0] reg_data_out;  // 0x00  R/W
// DATA_IN (0x04) is combinatorially sourced from gpio_in — no storage needed
reg [GPIO_WIDTH-1:0] reg_dir;       // 0x08  R/W  1=output, 0=input
reg [GPIO_WIDTH-1:0] reg_irq_en;    // 0x0C  R/W
reg [GPIO_WIDTH-1:0] reg_irq_stat;  // 0x10  W1C

// -------------------------------------------------------------------------
// gpio_out: always reflects DATA_OUT register
// (the external tri-state buffer, if any, is gated by DIR outside this block)
// -------------------------------------------------------------------------
always @(*) begin
    gpio_out = reg_data_out;
end

// -------------------------------------------------------------------------
// gpio_irq: any enabled sticky flag
// -------------------------------------------------------------------------
assign gpio_irq = |(reg_irq_stat & reg_irq_en);

// -------------------------------------------------------------------------
// AXI4-Lite Write Path
// Independently latch AW and W; write register when both are present;
// issue B response; de-assert ready while latch is full.
// reg_irq_stat is also written here (W1C) and SET by edge detection below;
// both are kept in this single always block to avoid multiple drivers.
// -------------------------------------------------------------------------
reg                  aw_latch_v;
reg [ADDR_WIDTH-1:0] aw_latch_addr;
reg [ID_WIDTH-1:0]   aw_latch_id;

reg                  w_latch_v;
reg [DATA_WIDTH-1:0] w_latch_data;
reg [STRB_WIDTH-1:0] w_latch_strb;

reg               b_valid_r;
reg [ID_WIDTH-1:0] b_id_r;

// Rising-edge detection state (lives in write-path block to share reg_irq_stat)
reg [GPIO_WIDTH-1:0] gpio_in_prev;

assign s_axi_awready = !aw_latch_v;
assign s_axi_wready  = !w_latch_v;
assign s_axi_bvalid  = b_valid_r;
assign s_axi_bid     = b_id_r;
assign s_axi_bresp   = 2'b00;   // OKAY

// Write-enable flag: both AW and W latches are full
wire do_write = aw_latch_v & w_latch_v;

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
        reg_data_out  <= {GPIO_WIDTH{1'b0}};
        reg_dir       <= {GPIO_WIDTH{1'b0}};
        reg_irq_en    <= {GPIO_WIDTH{1'b0}};
        reg_irq_stat  <= {GPIO_WIDTH{1'b0}};
        gpio_in_prev  <= {GPIO_WIDTH{1'b0}};
    end else begin

        // ----------------------------------------------------------------
        // Rising-edge detection: always update previous sample and OR new
        // rising edges into the sticky flag register.
        // W1C write (below) uses the post-set value so it can atomically
        // clear freshly-set bits in the same cycle if needed.
        // ----------------------------------------------------------------
        gpio_in_prev <= gpio_in;
        reg_irq_stat <= reg_irq_stat | (gpio_in & ~gpio_in_prev);

        // ----------------------------------------------------------------
        // Capture AW channel
        // ----------------------------------------------------------------
        if (!aw_latch_v && s_axi_awvalid) begin
            aw_latch_v    <= 1'b1;
            aw_latch_addr <= s_axi_awaddr;
            aw_latch_id   <= s_axi_awid;
        end

        // ----------------------------------------------------------------
        // Capture W channel
        // ----------------------------------------------------------------
        if (!w_latch_v && s_axi_wvalid) begin
            w_latch_v    <= 1'b1;
            w_latch_data <= s_axi_wdata;
            w_latch_strb <= s_axi_wstrb;
        end

        // ----------------------------------------------------------------
        // Perform register write when both AW and W are latched.
        // Because non-blocking assignments in the same always block share
        // the same scheduling step, the rising-edge OR above and the W1C
        // clear below see the same reg_irq_stat RHS (the value at the
        // start of the cycle).  The W1C assignment is ordered AFTER the
        // edge-set assignment so it takes precedence for any bit the CPU
        // clears — consistent with W1C semantics.
        // ----------------------------------------------------------------
        if (do_write) begin
            case (aw_latch_addr[4:2])
                3'h0: begin // DATA_OUT  R/W  (byte-lane aware)
                    if (w_latch_strb[0]) reg_data_out[ 7: 0] <= w_latch_data[ 7: 0];
                    if (w_latch_strb[1]) reg_data_out[15: 8] <= w_latch_data[15: 8];
                    if (w_latch_strb[2]) reg_data_out[23:16] <= w_latch_data[23:16];
                    if (w_latch_strb[3]) reg_data_out[31:24] <= w_latch_data[31:24];
                end
                3'h1: begin // DATA_IN   RO — silently ignore write
                end
                3'h2: begin // DIR       R/W  (byte-lane aware)
                    if (w_latch_strb[0]) reg_dir[ 7: 0] <= w_latch_data[ 7: 0];
                    if (w_latch_strb[1]) reg_dir[15: 8] <= w_latch_data[15: 8];
                    if (w_latch_strb[2]) reg_dir[23:16] <= w_latch_data[23:16];
                    if (w_latch_strb[3]) reg_dir[31:24] <= w_latch_data[31:24];
                end
                3'h3: begin // IRQ_EN    R/W  (byte-lane aware)
                    if (w_latch_strb[0]) reg_irq_en[ 7: 0] <= w_latch_data[ 7: 0];
                    if (w_latch_strb[1]) reg_irq_en[15: 8] <= w_latch_data[15: 8];
                    if (w_latch_strb[2]) reg_irq_en[23:16] <= w_latch_data[23:16];
                    if (w_latch_strb[3]) reg_irq_en[31:24] <= w_latch_data[31:24];
                end
                3'h4: begin // IRQ_STAT  W1C
                    // Overrides the edge-set assignment above (last NBA wins).
                    // New rising edges that occur THIS cycle are still ORed in
                    // via the earlier statement; the W1C only clears bits the
                    // CPU explicitly wrote as 1.
                    reg_irq_stat <= (reg_irq_stat | (gpio_in & ~gpio_in_prev))
                                    & ~w_latch_data;
                end
                default: ; // unmapped address — ignore
            endcase

            aw_latch_v <= 1'b0;
            w_latch_v  <= 1'b0;
            b_valid_r  <= 1'b1;
            b_id_r     <= aw_latch_id;
        end

        // ----------------------------------------------------------------
        // Retire B response
        // ----------------------------------------------------------------
        if (b_valid_r && s_axi_bready) begin
            b_valid_r <= 1'b0;
        end

    end
end

// -------------------------------------------------------------------------
// AXI4-Lite Read Path
// Accept AR, register data into rdata, present R channel with rlast=1.
// -------------------------------------------------------------------------
reg                  ar_active_r;
reg [ID_WIDTH-1:0]   ar_id_r;
reg [DATA_WIDTH-1:0] ar_rdata_r;

assign s_axi_arready = !ar_active_r;
assign s_axi_rvalid  = ar_active_r;
assign s_axi_rid     = ar_id_r;
assign s_axi_rdata   = ar_rdata_r;
assign s_axi_rresp   = 2'b00;   // OKAY
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
            case (s_axi_araddr[4:2])
                3'h0: ar_rdata_r <= {{(DATA_WIDTH-GPIO_WIDTH){1'b0}}, reg_data_out};
                3'h1: ar_rdata_r <= {{(DATA_WIDTH-GPIO_WIDTH){1'b0}}, gpio_in};
                3'h2: ar_rdata_r <= {{(DATA_WIDTH-GPIO_WIDTH){1'b0}}, reg_dir};
                3'h3: ar_rdata_r <= {{(DATA_WIDTH-GPIO_WIDTH){1'b0}}, reg_irq_en};
                3'h4: ar_rdata_r <= {{(DATA_WIDTH-GPIO_WIDTH){1'b0}}, reg_irq_stat};
                default: ar_rdata_r <= 32'hDEAD_BEEF;
            endcase
        end

        if (ar_active_r && s_axi_rready) begin
            ar_active_r <= 1'b0;
        end

    end
end

endmodule

`resetall
