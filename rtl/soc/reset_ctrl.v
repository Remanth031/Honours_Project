// =============================================================================
// reset_ctrl.v  –  Reset & Watchdog Controller Slave (AXI4-Lite)
// Address: 0x2007_0000  Size: 4 KB (12-bit slave window)
// Access: VeeR CPU (R/W per register permissions)
//
// Register Map (word-addressed, 32-bit):
//  0x00  RESET_CAUSE  [2:0]  [0]=POR, [1]=WDT, [2]=SOFT  (RO, clear-on-read)
//  0x04  SOFT_RESET   WO     write 0xDEAD_BEEF → one-cycle sys_reset_req pulse
//  0x08  WDT_CTRL     R/W    [0]=WDT_EN
//  0x0C  WDT_LOAD     R/W    32-bit countdown load value (clock cycles)
//  0x10  WDT_KICK     WO     any write reloads the watchdog counter
//  0x14  WDT_STATUS   RO     [0]=WDT_EXPIRED
//
// Sideband:
//  por_reset    – active-high power-on-reset input from SoC top
//  sys_reset_req – active-high one-cycle reset request output to SoC top
//  wdt_irq      – pre-warning IRQ when WDT counter < WDT_LOAD/16
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module reset_ctrl #(
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

    // ---- Sideband ports ----
    input  wire        por_reset,      // power-on-reset from top-level (active-high)
    output wire        sys_reset_req,  // active-high reset request to SoC top
    output wire        wdt_irq         // pre-warning IRQ: WDT counter < WDT_LOAD/16
);

// =========================================================================
// Address offset decode (12-bit window, word-indexed via [5:2])
// =========================================================================
localparam OFFSET_RESET_CAUSE = 3'h0; // 0x00
localparam OFFSET_SOFT_RESET  = 3'h1; // 0x04
localparam OFFSET_WDT_CTRL    = 3'h2; // 0x08
localparam OFFSET_WDT_LOAD    = 3'h3; // 0x0C
localparam OFFSET_WDT_KICK    = 3'h4; // 0x10
localparam OFFSET_WDT_STATUS  = 3'h5; // 0x14

localparam SOFT_RESET_KEY = 32'hDEAD_BEEF;

// =========================================================================
// Internal registers
// =========================================================================
// RESET_CAUSE  0x00 – sticky bits, clear-on-read
reg [2:0] reg_reset_cause;   // [0]=POR, [1]=WDT, [2]=SOFT

// WDT_CTRL  0x08
reg       reg_wdt_en;

// WDT_LOAD  0x0C
reg [31:0] reg_wdt_load;

// WDT_STATUS  0x14 – set on expiry, cleared when counter is reloaded
reg        reg_wdt_expired;

// =========================================================================
// Watchdog counter
// =========================================================================
reg [31:0] wdt_counter;

// Internal event signals
reg  soft_reset_pulse;   // one-cycle: soft-reset triggered this cycle
reg  wdt_expire_pulse;   // one-cycle: watchdog just expired this cycle

// Threshold: fire IRQ when counter < WDT_LOAD/16 (arithmetic right-shift by 4)
wire [31:0] wdt_irq_thresh = {4'b0000, reg_wdt_load[31:4]};

assign wdt_irq       = reg_wdt_en && (wdt_counter < wdt_irq_thresh) && (wdt_counter != 32'd0);
assign sys_reset_req = soft_reset_pulse | wdt_expire_pulse;

// =========================================================================
// AXI4-Lite Write Path
// =========================================================================
// Latch AW and W independently, fire register write when both ready
reg                  aw_latch_v;
reg [ADDR_WIDTH-1:0] aw_latch_addr;
reg [ID_WIDTH-1:0]   aw_latch_id;
reg                  w_latch_v;
reg [DATA_WIDTH-1:0] w_latch_data;
reg [STRB_WIDTH-1:0] w_latch_strb;
reg                  b_valid_r;
reg [ID_WIDTH-1:0]   b_id_r;

// Internal write-fire signals decoded from the latched transaction
reg  do_write;
wire [2:0] wr_offset = aw_latch_addr[4:2]; // bits [4:2] select register word

assign s_axi_awready = !aw_latch_v;
assign s_axi_wready  = !w_latch_v;
assign s_axi_bvalid  = b_valid_r;
assign s_axi_bid     = b_id_r;
assign s_axi_bresp   = 2'b00; // OKAY

// Internal kick/soft-reset decode
wire wr_is_kick       = do_write && (wr_offset == OFFSET_WDT_KICK);
wire wr_is_soft_reset = do_write && (wr_offset == OFFSET_SOFT_RESET) &&
                        (w_latch_data == SOFT_RESET_KEY);

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
        do_write      <= 1'b0;
        // Registers
        reg_wdt_en      <= 1'b0;
        reg_wdt_load    <= 32'd0;
    end else begin
        do_write <= 1'b0; // default: clear each cycle

        // Capture AW channel
        if (!aw_latch_v && s_axi_awvalid) begin
            aw_latch_v    <= 1'b1;
            aw_latch_addr <= s_axi_awaddr;
            aw_latch_id   <= s_axi_awid;
        end

        // Capture W channel
        if (!w_latch_v && s_axi_wvalid) begin
            w_latch_v    <= 1'b1;
            w_latch_data <= s_axi_wdata;
            w_latch_strb <= s_axi_wstrb;
        end

        // Fire write when both channels are captured
        if (aw_latch_v && w_latch_v && !b_valid_r) begin
            do_write   <= 1'b1;
            aw_latch_v <= 1'b0;
            w_latch_v  <= 1'b0;
            b_valid_r  <= 1'b1;
            b_id_r     <= aw_latch_id;

            // Register write decode
            case (wr_offset)
                OFFSET_WDT_CTRL: reg_wdt_en   <= w_latch_data[0];
                OFFSET_WDT_LOAD: reg_wdt_load <= w_latch_data;
                // SOFT_RESET, WDT_KICK, RESET_CAUSE (RO), WDT_STATUS (RO):
                // handled as side-effects below (soft_reset_pulse, wdt kick)
                default: ;
            endcase
        end

        // Clear B-channel handshake
        if (b_valid_r && s_axi_bready) b_valid_r <= 1'b0;
    end
end

// =========================================================================
// AXI4-Lite Read Path
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

// clear-on-read flag: set when RESET_CAUSE is being read this cycle
wire rd_cause_clear = !ar_active_r && s_axi_arvalid &&
                      (s_axi_araddr[4:2] == OFFSET_RESET_CAUSE);

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
                OFFSET_RESET_CAUSE: ar_rdata_r <= {29'd0, reg_reset_cause};
                OFFSET_WDT_CTRL:    ar_rdata_r <= {31'd0, reg_wdt_en};
                OFFSET_WDT_LOAD:    ar_rdata_r <= reg_wdt_load;
                OFFSET_WDT_STATUS:  ar_rdata_r <= {31'd0, reg_wdt_expired};
                // WO registers / undefined → read-as-zero
                default:            ar_rdata_r <= 32'd0;
            endcase
        end
        if (ar_active_r && s_axi_rready) ar_active_r <= 1'b0;
    end
end

// =========================================================================
// Soft-reset pulse generation
// =========================================================================
always @(posedge clk) begin
    if (rst) begin
        soft_reset_pulse <= 1'b0;
    end else begin
        // Assert for exactly one cycle when magic word is written
        soft_reset_pulse <= wr_is_soft_reset;
    end
end

// =========================================================================
// Watchdog countdown and expiry
// =========================================================================
always @(posedge clk) begin
    if (rst) begin
        wdt_counter      <= 32'd0;
        wdt_expire_pulse <= 1'b0;
        reg_wdt_expired  <= 1'b0;
    end else begin
        wdt_expire_pulse <= 1'b0; // default: clear each cycle

        if (!reg_wdt_en) begin
            // WDT disabled: hold counter at load value, clear expired status
            wdt_counter     <= reg_wdt_load;
            reg_wdt_expired <= 1'b0;
        end else begin
            // WDT enabled
            if (wr_is_kick) begin
                // Kick: reload counter
                wdt_counter     <= reg_wdt_load;
                reg_wdt_expired <= 1'b0;
            end else if (wdt_counter == 32'd0) begin
                // Counter has reached zero → assert one-cycle expiry pulse
                // and reload to prevent continuous triggering
                wdt_expire_pulse <= 1'b1;
                reg_wdt_expired  <= 1'b1;
                wdt_counter      <= reg_wdt_load; // reload after expiry
            end else begin
                // Normal countdown
                wdt_counter <= wdt_counter - 32'd1;
            end
        end
    end
end

// =========================================================================
// RESET_CAUSE register – sticky bits, set by events, clear-on-read
// =========================================================================
always @(posedge clk) begin
    if (rst) begin
        reg_reset_cause <= 3'b000;
    end else begin
        // Set bits on events (sticky)
        if (por_reset)          reg_reset_cause[0] <= 1'b1;
        if (wdt_expire_pulse)   reg_reset_cause[1] <= 1'b1;
        if (wr_is_soft_reset)   reg_reset_cause[2] <= 1'b1;

        // Clear-on-read: clear all bits when RESET_CAUSE is read
        // The read captures value first (combinational mux above), then clears
        if (rd_cause_clear) begin
            // Only clear bits that were not simultaneously set this cycle
            // to avoid losing a cause that fires on the exact same cycle as the read.
            // Priority: set wins over clear.
            if (!por_reset)        reg_reset_cause[0] <= 1'b0;
            if (!wdt_expire_pulse) reg_reset_cause[1] <= 1'b0;
            if (!wr_is_soft_reset) reg_reset_cause[2] <= 1'b0;
        end
    end
end

endmodule

`resetall
