// =============================================================================
// boot_rom.v  –  Boot ROM Slave (AXI4, Read-Only)
// Address: 0x3000_0000  Size: 4 KB (1024 × 32-bit words)
// Access: Read-only; write attempts return SLVERR
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module boot_rom #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8,
    // ROM depth in 32-bit words  (4 KB = 1024 words)
    parameter ROM_DEPTH  = 1024
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
// ROM array — block-RAM style, word-addressed, read-only
// Synthesis attribute forces mapping to block RAM on FPGA targets.
// $readmemh initialises the ROM; on synthesis with a missing .vmem file
// the tool will fall back to zero-initialised block RAM.
// -------------------------------------------------------------------------
(* rom_style = "block" *)
reg [DATA_WIDTH-1:0] rom_mem [0:ROM_DEPTH-1];

`ifdef SIMULATION
    initial $readmemh("boot_rom.vmem", rom_mem);
`else
    // For synthesis: $readmemh is still honoured by most tools (Vivado,
    // Quartus) when the .vmem file is present in the project.  If absent,
    // the array is zero-initialised — safe for a boot ROM stub.
    initial $readmemh("boot_rom.vmem", rom_mem);
`endif

// -------------------------------------------------------------------------
// Address decode helper
// The slave occupies a 12-bit window (4 KB) at 0x3000_0000.
// Word index = addr[11:2]  (bits [1:0] are the byte offset, ignored).
// -------------------------------------------------------------------------
localparam ADDR_BASE = 32'h3000_0000;
localparam ADDR_MASK = 12'hFFF;         // 12-bit window

// -------------------------------------------------------------------------
// Write path — ROM is read-only; accept AW + W beats and return SLVERR.
// No data is actually written to rom_mem.
// -------------------------------------------------------------------------
reg                  aw_active;
reg [ID_WIDTH-1:0]   aw_id_r;
reg [7:0]            aw_len_r;
reg [7:0]            aw_beat;

assign s_axi_awready = !aw_active;
assign s_axi_wready  = aw_active;

always @(posedge clk) begin
    if (rst) begin
        aw_active <= 1'b0;
        aw_beat   <= 8'd0;
    end else begin
        // Latch write address
        if (!aw_active && s_axi_awvalid) begin
            aw_active <= 1'b1;
            aw_id_r   <= s_axi_awid;
            aw_len_r  <= s_axi_awlen;
            aw_beat   <= 8'd0;
        end
        // Absorb write data beats — do NOT write to rom_mem
        if (aw_active && s_axi_wvalid) begin
            if (s_axi_wlast)
                aw_active <= 1'b0;
            else
                aw_beat <= aw_beat + 1;
        end
    end
end

// Write response — always SLVERR (2'b10) because ROM is read-only
reg                b_valid;
reg [ID_WIDTH-1:0] b_id;

always @(posedge clk) begin
    if (rst) begin
        b_valid <= 1'b0;
        b_id    <= {ID_WIDTH{1'b0}};
    end else begin
        if (aw_active && s_axi_wvalid && s_axi_wlast) begin
            b_valid <= 1'b1;
            b_id    <= aw_id_r;
        end else if (b_valid && s_axi_bready) begin
            b_valid <= 1'b0;
        end
    end
end

assign s_axi_bvalid = b_valid;
assign s_axi_bid    = b_id;
assign s_axi_bresp  = 2'b10; // SLVERR — write to ROM not permitted

// -------------------------------------------------------------------------
// Read path — burst reads identical in structure to data_mem.v
// -------------------------------------------------------------------------
reg                  ar_active;
reg [11:2]           ar_addr_r;   // 10-bit word index within 4 KB window
reg [ID_WIDTH-1:0]   ar_id_r;
reg [7:0]            ar_len_r;
reg [7:0]            ar_beat;

assign s_axi_arready = !ar_active;

always @(posedge clk) begin
    if (rst) begin
        ar_active <= 1'b0;
        ar_beat   <= 8'd0;
    end else begin
        // Latch read address
        if (!ar_active && s_axi_arvalid) begin
            ar_active <= 1'b1;
            // Capture the 10-bit word index from the 12-bit slave window
            ar_addr_r <= s_axi_araddr[11:2];
            ar_id_r   <= s_axi_arid;
            ar_len_r  <= s_axi_arlen;
            ar_beat   <= 8'd0;
        end
        // Advance burst on each accepted read data beat
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
// Word-indexed read: base word + beat offset, masked to ROM_DEPTH
assign s_axi_rdata  = rom_mem[(ar_addr_r + ar_beat) % ROM_DEPTH];
assign s_axi_rresp  = 2'b00; // OKAY
assign s_axi_rlast  = ar_active && (ar_beat == ar_len_r);

endmodule

`resetall
