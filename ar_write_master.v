// =============================================================================
// ar_write_master.v  –  Array Rasterizer Write Master (AXI4)
// Interconnect port: S02
// Accesses: Framebuffer ONLY (writes rasterized pixel data)
//
// This master issues burst writes to the framebuffer as the rasterizer engine
// produces pixel data.  Pixel words are buffered and flushed in bursts to
// improve bus utilisation.
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module ar_write_master #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8,
    parameter MAX_BURST  = 16    // write burst length in beats
)(
    input  wire                  clk,
    input  wire                  rst,

    // ---- Pixel input from AR engine ----
    input  wire [DATA_WIDTH-1:0] pixel_data,     // pixel word (XRGB)
    input  wire [ADDR_WIDTH-1:0] pixel_addr,     // framebuffer address for this pixel
    input  wire                  pixel_valid,    // pixel data valid
    output wire                  pixel_ready,    // master ready to accept pixel

    output reg                   busy,
    output reg                   done,           // pulse: all pixels written + responses received

    // ---- AXI4 Master Interface (→ interconnect S02) ----
    // Read address – unused (write-only master, tied off)
    output wire [ID_WIDTH-1:0]   m_axi_arid,
    output wire [ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [7:0]            m_axi_arlen,
    output wire [2:0]            m_axi_arsize,
    output wire [1:0]            m_axi_arburst,
    output wire                  m_axi_arlock,
    output wire [3:0]            m_axi_arcache,
    output wire [2:0]            m_axi_arprot,
    output wire [3:0]            m_axi_arqos,
    output wire                  m_axi_arvalid,
    input  wire                  m_axi_arready,
    input  wire [ID_WIDTH-1:0]   m_axi_rid,
    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output wire                  m_axi_rready,
    // Write address channel
    output reg  [ID_WIDTH-1:0]   m_axi_awid,
    output reg  [ADDR_WIDTH-1:0] m_axi_awaddr,
    output reg  [7:0]            m_axi_awlen,
    output wire [2:0]            m_axi_awsize,
    output wire [1:0]            m_axi_awburst,
    output wire                  m_axi_awlock,
    output wire [3:0]            m_axi_awcache,
    output wire [2:0]            m_axi_awprot,
    output wire [3:0]            m_axi_awqos,
    output reg                   m_axi_awvalid,
    input  wire                  m_axi_awready,
    // Write data channel
    output reg  [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [STRB_WIDTH-1:0] m_axi_wstrb,
    output reg                   m_axi_wlast,
    output reg                   m_axi_wvalid,
    input  wire                  m_axi_wready,
    // Write response channel
    input  wire [ID_WIDTH-1:0]   m_axi_bid,
    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output wire                  m_axi_bready
);

// ---- Tie off read path (write-only master) ----
assign m_axi_arid    = {ID_WIDTH{1'b0}};
assign m_axi_araddr  = {ADDR_WIDTH{1'b0}};
assign m_axi_arlen   = 8'h00;
assign m_axi_arsize  = 3'b010;
assign m_axi_arburst = 2'b01;
assign m_axi_arlock  = 1'b0;
assign m_axi_arcache = 4'b0000;
assign m_axi_arprot  = 3'b000;
assign m_axi_arqos   = 4'h0;
assign m_axi_arvalid = 1'b0;
assign m_axi_rready  = 1'b1;

// ---- Fixed write channel signals ----
assign m_axi_awsize  = 3'b010;   // 4-byte
assign m_axi_awburst = 2'b01;    // INCR
assign m_axi_awlock  = 1'b0;
assign m_axi_awcache = 4'b0010;
assign m_axi_awprot  = 3'b000;
assign m_axi_awqos   = 4'h0;
assign m_axi_wstrb   = {STRB_WIDTH{1'b1}}; // all byte lanes
assign m_axi_bready  = 1'b1;    // always accept write responses

// ---- Simple pixel write queue (depth = MAX_BURST) ----
// In a real design, replace with a proper FIFO. Here we use a shift register
// for synthesis simplicity.
reg [DATA_WIDTH-1:0] pix_buf  [0:MAX_BURST-1];
reg [ADDR_WIDTH-1:0] addr_buf [0:MAX_BURST-1];
reg [4:0]            buf_cnt;  // number of pixels in buffer

assign pixel_ready = (buf_cnt < MAX_BURST) && !busy;

integer i;
always @(posedge clk) begin
    if (rst) begin
        buf_cnt <= 0;
    end else begin
        if (pixel_valid && pixel_ready) begin
            pix_buf [buf_cnt] <= pixel_data;
            addr_buf[buf_cnt] <= pixel_addr;
            buf_cnt           <= buf_cnt + 1;
        end
    end
end

// ---- Write state machine ----
localparam W_IDLE  = 3'd0,
           W_AW    = 3'd1,
           W_DATA  = 3'd2,
           W_WAIT  = 3'd3,
           W_DONE  = 3'd4;

reg [2:0]  w_state;
reg [4:0]  beat;
reg [7:0]  tx_id;

always @(posedge clk) begin
    if (rst) begin
        w_state      <= W_IDLE;
        busy         <= 1'b0;
        done         <= 1'b0;
        m_axi_awvalid<= 1'b0;
        m_axi_wvalid <= 1'b0;
        m_axi_wlast  <= 1'b0;
        beat         <= 5'd0;
        tx_id        <= 8'd0;
    end else begin
        done <= 1'b0;

        case (w_state)
            W_IDLE: begin
                // Flush when buffer is full or a flush signal could be added here
                if (buf_cnt == MAX_BURST) begin
                    busy           <= 1'b1;
                    m_axi_awid     <= tx_id;
                    m_axi_awaddr   <= addr_buf[0];
                    m_axi_awlen    <= MAX_BURST - 1;
                    m_axi_awvalid  <= 1'b1;
                    beat           <= 5'd0;
                    w_state        <= W_AW;
                end
            end

            W_AW: begin
                if (m_axi_awvalid && m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                    w_state       <= W_DATA;
                end
            end

            W_DATA: begin
                m_axi_wvalid <= 1'b1;
                m_axi_wdata  <= pix_buf[beat];
                m_axi_wlast  <= (beat == MAX_BURST - 1);
                if (m_axi_wvalid && m_axi_wready) begin
                    if (beat == MAX_BURST - 1) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_wlast  <= 1'b0;
                        w_state      <= W_WAIT;
                    end else begin
                        beat <= beat + 1;
                    end
                end
            end

            W_WAIT: begin
                // Wait for write response
                if (m_axi_bvalid) begin
                    buf_cnt <= buf_cnt - MAX_BURST;
                    tx_id   <= tx_id + 1;
                    busy    <= 1'b0;
                    done    <= 1'b1;
                    w_state <= W_IDLE;
                end
            end

            default: w_state <= W_IDLE;
        endcase
    end
end

endmodule

`resetall
