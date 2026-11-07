// =============================================================================
// ar_read_master.v  –  Array Rasterizer Read Master (AXI4)
// Interconnect port: S01
// Accesses: Data Memory ONLY (reads vertex/primitive data)
//
// This master issues burst reads to the data memory to fetch vertex/endpoint
// data for the rasterizer engine.  The AR engine drives this port after the
// CPU has written a draw command to the AR Control slave.
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module ar_read_master #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8,
    parameter MAX_BURST  = 16   // max burst length (beats)
)(
    input  wire                  clk,
    input  wire                  rst,

    // ---- Control from AR engine ----
    input  wire                  start,          // start a burst read
    input  wire [ADDR_WIDTH-1:0] base_addr,      // starting address
    input  wire [15:0]           beat_count,     // total number of 32-bit words to read
    output reg                   busy,           // reading in progress
    output reg                   done,           // pulse: all data received
    output wire [DATA_WIDTH-1:0] rdata,          // read data word (valid when rvalid_out=1)
    output wire                  rvalid_out,     // read data valid to AR engine

    // ---- AXI4 Master Interface (→ interconnect S01) ----
    // Write address – unused (read-only master, tied off)
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
    // Read address channel
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
    // Read data channel
    input  wire [ID_WIDTH-1:0]   m_axi_rid,
    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output wire                  m_axi_rready
);

// ---- Tie off write path (read-only master) ----
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

// ---- Fixed read channel signals ----
assign m_axi_arsize  = 3'b010;   // 4-byte transfers
assign m_axi_arburst = 2'b01;    // INCR
assign m_axi_arlock  = 1'b0;
assign m_axi_arcache = 4'b0010;  // normal non-cacheable bufferable
assign m_axi_arprot  = 3'b000;
assign m_axi_arqos   = 4'h0;
assign m_axi_rready  = busy;     // accept data whenever busy

assign rdata      = m_axi_rdata;
assign rvalid_out = m_axi_rvalid && busy;

// ---- Burst state machine ----
// Tracks how many beats remain across potentially multiple AXI bursts.
reg [15:0] beats_remaining;
reg [15:0] beats_inflight;

localparam IDLE    = 2'd0,
           ISSUE   = 2'd1,
           RECEIVE = 2'd2,
           FINISH  = 2'd3;

reg [1:0] state;

always @(posedge clk) begin
    if (rst) begin
        state           <= IDLE;
        busy            <= 1'b0;
        done            <= 1'b0;
        m_axi_arvalid   <= 1'b0;
        m_axi_arid      <= {ID_WIDTH{1'b0}};
        m_axi_araddr    <= {ADDR_WIDTH{1'b0}};
        m_axi_arlen     <= 8'h00;
        beats_remaining <= 16'd0;
        beats_inflight  <= 16'd0;
    end else begin
        done <= 1'b0; // default pulse-clear

        case (state)
            IDLE: begin
                if (start) begin
                    busy            <= 1'b1;
                    beats_remaining <= beat_count;
                    m_axi_araddr    <= base_addr;
                    m_axi_arid      <= {ID_WIDTH{1'b0}};
                    state           <= ISSUE;
                end
            end

            ISSUE: begin
                // Calculate burst length (capped at MAX_BURST)
                beats_inflight  <= (beats_remaining > MAX_BURST) ? MAX_BURST : beats_remaining;
                m_axi_arlen     <= (beats_remaining > MAX_BURST) ? (MAX_BURST-1) : (beats_remaining-1);
                m_axi_arvalid   <= 1'b1;
                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid   <= 1'b0;
                    state           <= RECEIVE;
                end
            end

            RECEIVE: begin
                if (m_axi_rvalid) begin
                    beats_inflight <= beats_inflight - 1;
                    if (m_axi_rlast) begin
                        beats_remaining <= beats_remaining - beats_inflight;
                        m_axi_araddr    <= m_axi_araddr + (beats_inflight << 2);
                        if (beats_remaining <= beats_inflight)
                            state <= FINISH;
                        else
                            state <= ISSUE;
                    end
                end
            end

            FINISH: begin
                busy  <= 1'b0;
                done  <= 1'b1;
                state <= IDLE;
            end
        endcase
    end
end

endmodule

`resetall
