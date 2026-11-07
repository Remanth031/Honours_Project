// =============================================================================
// spi.v  –  AXI4-Lite SPI Master Controller (Array Rasterizer SoC)
// Address: 0x2005_0000  Size: 4 KB (12-bit slave window)
// Access: VeeR CPU (R/W)
//
// Register Map (byte-addressed, 32-bit words):
//  0x00  CTRL       R/W  [0]=EN, [1]=CPOL, [2]=CPHA, [7:3]=CLK_DIV[4:0]
//  0x04  TX_DATA    W    [7:0]=byte to transmit; writing here starts a transfer
//  0x08  RX_DATA    R    [7:0]=last received byte
//  0x0C  STATUS     R    [0]=BUSY, [1]=TX_EMPTY, [2]=RX_VALID
//  0x10  IRQ_EN     R/W  [0]=DONE_IE
//  0x14  IRQ_STAT   R/W  [0]=DONE  (W1C)
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module spi #(
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

    // ---- Physical SPI pins ----
    output wire  spi_sclk,
    output wire  spi_mosi,
    input  wire  spi_miso,
    output wire  spi_cs_n,

    // ---- Interrupt to CPU ----
    output wire  spi_irq
);

// =========================================================================
// AXI4-Lite Write Path internal regs   (identical style to ar_control.v)
// =========================================================================
reg                  aw_latch_v;
reg [ADDR_WIDTH-1:0] aw_latch_addr;
reg [ID_WIDTH-1:0]   aw_latch_id;
reg                  w_latch_v;
reg [DATA_WIDTH-1:0] w_latch_data;
reg [STRB_WIDTH-1:0] w_latch_strb;  // captured but unused for byte-only regs
reg                  b_valid_r;
reg [ID_WIDTH-1:0]   b_id_r;

// ---- Configuration registers (driven exclusively by AXI write path) ----
reg [7:0]  reg_ctrl;      // 0x00 : [7:3]=CLK_DIV[4:0], [2]=CPHA, [1]=CPOL, [0]=EN
reg [7:0]  reg_tx_data;   // 0x04 : TX byte written by CPU
reg        reg_irq_en;    // 0x10 : [0]=DONE_IE

// Decoded control fields
wire        ctrl_en     = reg_ctrl[0];
wire        ctrl_cpol   = reg_ctrl[1];
wire        ctrl_cpha   = reg_ctrl[2];
wire [4:0]  ctrl_clkdiv = reg_ctrl[7:3];

// ---- Combinatorial event wires from AXI write path to SPI engine ----
// Both latches are full when (aw_latch_v & w_latch_v); decoded per address.
wire        axi_tx_write;    // CPU wrote 0x04 TX_DATA this cycle
wire        axi_irq_w1c;     // CPU wrote 0x14 IRQ_STAT (W1C) this cycle
wire        axi_irq_clr_bit; // bit-0 of the W1C write

assign axi_tx_write   = aw_latch_v & w_latch_v & (aw_latch_addr[4:2] == 3'h1);
assign axi_irq_w1c    = aw_latch_v & w_latch_v & (aw_latch_addr[4:2] == 3'h5);
assign axi_irq_clr_bit = w_latch_data[0];

assign s_axi_awready = !aw_latch_v;
assign s_axi_wready  = !w_latch_v;
assign s_axi_bvalid  = b_valid_r;
assign s_axi_bid     = b_id_r;
assign s_axi_bresp   = 2'b00;

always @(posedge clk) begin
    if (rst) begin
        aw_latch_v   <= 1'b0;
        w_latch_v    <= 1'b0;
        b_valid_r    <= 1'b0;
        b_id_r       <= {ID_WIDTH{1'b0}};
        reg_ctrl     <= 8'h00;
        reg_tx_data  <= 8'h00;
        reg_irq_en   <= 1'b0;
    end else begin
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
        // Write register when both captured
        if (aw_latch_v && w_latch_v) begin
            case (aw_latch_addr[4:2])
                3'h0: reg_ctrl    <= w_latch_data[7:0];  // CTRL
                3'h1: reg_tx_data <= w_latch_data[7:0];  // TX_DATA
                // 0x08 RX_DATA  – read-only, writes ignored
                // 0x0C STATUS   – read-only, writes ignored
                3'h4: reg_irq_en  <= w_latch_data[0];   // IRQ_EN
                // 0x14 IRQ_STAT – W1C handled in SPI engine block
                default: ;
            endcase
            aw_latch_v <= 1'b0;
            w_latch_v  <= 1'b0;
            b_valid_r  <= 1'b1;
            b_id_r     <= aw_latch_id;
        end
        // B-channel handshake
        if (b_valid_r && s_axi_bready)
            b_valid_r <= 1'b0;
    end
end

// =========================================================================
// SPI Engine
// All dynamic state is owned here in a single always block so there are
// no multiple-driver conflicts.  The only cross-block signals are the
// combinatorial wires axi_tx_write / axi_irq_w1c declared above and
// the wire axi_rx_read declared just before the read path.
// =========================================================================

// Clock divider counter
reg  [4:0]  clk_cnt;

// Engine state
reg         busy;           // transfer in progress
reg         tx_pending;     // CPU wrote TX_DATA, transfer queued
reg  [7:0]  shift_out;      // TX shift register (MSB first)
reg  [7:0]  shift_in;       // RX shift register
reg  [7:0]  reg_rx_data;    // 0x08 : last received byte
reg  [3:0]  bit_cnt;        // half-period counter 0..15
reg         sclk_r;         // SPI clock output register
reg         mosi_r;         // MOSI output register
reg         cs_n_r;         // CS_N output register
reg         tx_empty;       // STATUS[1] : no byte pending
reg         rx_valid;       // STATUS[2] : reg_rx_data is fresh
reg         done_pulse;     // one-cycle done event
reg         reg_irq_stat;   // 0x14 : [0]=DONE (W1C)

// sclk_tick fires for one cycle every half-SCLK period
wire sclk_tick = busy & (clk_cnt == ctrl_clkdiv);

// STATUS read-only register assembled from engine signals
wire [31:0] reg_status = {29'd0, rx_valid, tx_empty, busy};

// Combinatorial wire: AXI read path is sampling RX_DATA this cycle.
// Declared here (before the AXI read path block) but assigned after.
wire axi_rx_read;

always @(posedge clk) begin
    if (rst) begin
        clk_cnt      <= 5'd0;
        busy         <= 1'b0;
        tx_pending   <= 1'b0;
        shift_out    <= 8'h00;
        shift_in     <= 8'h00;
        reg_rx_data  <= 8'h00;
        bit_cnt      <= 4'd0;
        sclk_r       <= 1'b0;
        mosi_r       <= 1'b0;
        cs_n_r       <= 1'b1;
        tx_empty     <= 1'b1;
        rx_valid     <= 1'b0;
        done_pulse   <= 1'b0;
        reg_irq_stat <= 1'b0;
    end else begin
        // Default: clear one-cycle pulses
        done_pulse <= 1'b0;

        // ---- IRQ_STAT management ----
        // Set on done; W1C clear from AXI (both can occur on same cycle —
        // done wins to avoid losing an event that arrived simultaneously).
        if (axi_irq_w1c)
            reg_irq_stat <= reg_irq_stat & ~axi_irq_clr_bit;
        if (done_pulse)                   // done overrides clear
            reg_irq_stat <= 1'b1;

        // ---- Accept a TX_DATA write from AXI ----
        // axi_tx_write is high for exactly one clock cycle when the AXI
        // write path has both AW and W captured for address 0x04.
        if (axi_tx_write && ctrl_en && !busy) begin
            tx_pending <= 1'b1;
            tx_empty   <= 1'b0;
        end

        // ---- Clock divider ----
        if (!busy) begin
            clk_cnt <= 5'd0;
        end else if (clk_cnt == ctrl_clkdiv) begin
            clk_cnt <= 5'd0;
        end else begin
            clk_cnt <= clk_cnt + 5'd1;
        end

        // ---- SPI state machine ----
        if (!busy) begin
            sclk_r <= ctrl_cpol;            // hold SCLK at idle level

            if (tx_pending && ctrl_en) begin
                // Start a new transfer
                tx_pending <= 1'b0;
                busy       <= 1'b1;
                cs_n_r     <= 1'b0;
                bit_cnt    <= 4'd0;
                shift_out  <= reg_tx_data;  // reg_tx_data was updated this same
                                            // posedge by the AXI write block;
                                            // tx_pending was set one cycle later
                                            // so reg_tx_data is stable here.
                // CPHA=0: pre-drive MSB before the first clock edge.
                // CPHA=1: MOSI is driven on the first clock edge; idle to 0.
                mosi_r <= ctrl_cpha ? 1'b0 : reg_tx_data[7];
            end

        end else begin
            // Transfer active — act on each half-clock tick
            if (sclk_tick) begin
                sclk_r  <= ~sclk_r;    // toggle SCLK

                // bit_cnt[0]=0 → first half-period of each bit
                // bit_cnt[0]=1 → second half-period of each bit
                // bit_cnt[3:1] → bit index (0=MSB … 7=LSB)
                if (!ctrl_cpha) begin
                    // CPHA=0: sample on first (leading) edge,
                    //         drive next bit on second (trailing) edge.
                    if (!bit_cnt[0]) begin
                        // Leading edge: sample MISO
                        shift_in <= {shift_in[6:0], spi_miso};
                    end else begin
                        // Trailing edge: pre-drive next MOSI bit
                        if (bit_cnt[3:1] != 3'd7)
                            mosi_r <= shift_out[6 - bit_cnt[3:1]];
                    end
                end else begin
                    // CPHA=1: drive on first (leading) edge,
                    //         sample on second (trailing) edge.
                    if (!bit_cnt[0]) begin
                        // Leading edge: drive MOSI
                        mosi_r <= shift_out[7 - bit_cnt[3:1]];
                    end else begin
                        // Trailing edge: sample MISO
                        shift_in <= {shift_in[6:0], spi_miso};
                    end
                end

                bit_cnt <= bit_cnt + 4'd1;

                // After 16 half-periods all 8 bits are done
                if (bit_cnt == 4'd15) begin
                    busy        <= 1'b0;
                    cs_n_r      <= 1'b1;
                    sclk_r      <= ctrl_cpol;   // return SCLK to idle
                    reg_rx_data <= shift_in;    // latch received byte
                    rx_valid    <= 1'b1;
                    tx_empty    <= 1'b1;
                    done_pulse  <= 1'b1;
                end
            end
        end

        // ---- RX_DATA read clears rx_valid ----
        if (axi_rx_read)
            rx_valid <= 1'b0;
    end
end

// Physical output assignments
assign spi_sclk = sclk_r;
assign spi_mosi = mosi_r;
assign spi_cs_n = cs_n_r;
assign spi_irq  = reg_irq_stat & reg_irq_en;

// =========================================================================
// AXI4-Lite Read Path  (identical style to ar_control.v)
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

// axi_rx_read is high for the single cycle when AR is accepted for 0x08
assign axi_rx_read = !ar_active_r & s_axi_arvalid & (s_axi_araddr[4:2] == 3'h2);

always @(posedge clk) begin
    if (rst) begin
        ar_active_r <= 1'b0;
        ar_rdata_r  <= {DATA_WIDTH{1'b0}};
        ar_id_r     <= {ID_WIDTH{1'b0}};
    end else begin
        if (!ar_active_r && s_axi_arvalid) begin
            ar_active_r <= 1'b1;
            ar_id_r     <= s_axi_arid;
            case (s_axi_araddr[4:2])
                3'h0: ar_rdata_r <= {24'd0, reg_ctrl};
                3'h1: ar_rdata_r <= {24'd0, reg_tx_data};
                3'h2: ar_rdata_r <= {24'd0, reg_rx_data};  // RX_DATA
                3'h3: ar_rdata_r <= reg_status;
                3'h4: ar_rdata_r <= {31'd0, reg_irq_en};
                3'h5: ar_rdata_r <= {31'd0, reg_irq_stat};
                default: ar_rdata_r <= 32'hDEAD_BEEF;
            endcase
        end
        if (ar_active_r && s_axi_rready)
            ar_active_r <= 1'b0;
    end
end

endmodule

`resetall
