`resetall
`timescale 1ns / 1ps
`default_nettype none

// =============================================================================
// ar_engine.v  —  Array Rasterizer Engine for the AR SoC
// =============================================================================
//
// Connects ar_control (register slave) to ar_read_master (vertex DMA) and
// ar_write_master (pixel DMA).  Implements:
//   • IDLE   – wait for ar_start, latch config, go to FETCH
//   • FETCH  – pulse ar_rm_start, buffer incoming vertex words, wait for
//              ar_rm_done
//   • RAST   – Bresenham line raster; 1 line for PRIM_LINE, 3 for PRIM_TRI
//   • DONE   – pulse ar_done one cycle, back to IDLE
//   • ERROR  – pulse ar_error one cycle, back to IDLE
//
// Vertex word format (one 32-bit word per vertex):
//   [31:16] = Y (signed 16-bit)
//   [15: 0] = X (signed 16-bit)
//
// Pixel address = fb_base + (y * fb_stride) + (x * 4)
// Pixel data    = {8'h00, color[23:0]}
// =============================================================================

module ar_engine #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) (
    // -------------------------------------------------------------------------
    // Clock / Reset
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst,          // active-high synchronous reset

    // -------------------------------------------------------------------------
    // From ar_control
    // -------------------------------------------------------------------------
    input  wire        ar_start,
    input  wire        ar_reset,
    input  wire [1:0]  ar_prim_type,
    input  wire [31:0] ar_prim_base,
    input  wire [31:0] ar_prim_count,
    input  wire [23:0] ar_color,
    input  wire [31:0] ar_fb_base,
    input  wire [31:0] ar_fb_stride,

    // -------------------------------------------------------------------------
    // To ar_control
    // -------------------------------------------------------------------------
    output reg         ar_busy,
    output reg         ar_done,
    output reg         ar_error,

    // -------------------------------------------------------------------------
    // To / from ar_read_master
    // -------------------------------------------------------------------------
    output reg         ar_rm_start,
    output reg [31:0]  ar_rm_base_addr,
    output reg [15:0]  ar_rm_beat_count,
    input  wire        ar_rm_busy,
    input  wire        ar_rm_done,
    input  wire [31:0] ar_rm_rdata,
    input  wire        ar_rm_rvalid,

    // -------------------------------------------------------------------------
    // To / from ar_write_master
    // -------------------------------------------------------------------------
    output reg  [31:0] ar_wm_pixel_data,
    output reg  [31:0] ar_wm_pixel_addr,
    output reg         ar_wm_pixel_valid,
    input  wire        ar_wm_pixel_ready,
    input  wire        ar_wm_busy,
    input  wire        ar_wm_done
);

    // =========================================================================
    // State encoding
    // =========================================================================
    localparam [2:0]
        ST_IDLE  = 3'd0,
        ST_FETCH = 3'd1,
        ST_KICK  = 3'd2,   // one-cycle pulse for ar_rm_start
        ST_RAST  = 3'd3,
        ST_DONE  = 3'd4,
        ST_ERROR = 3'd5;

    // Sub-states within ST_RAST
    localparam [1:0]
        RS_INIT  = 2'd0,   // initialise Bresenham for current segment
        RS_PIXEL = 2'd1,   // present pixel, wait for ready
        RS_STEP  = 2'd2;   // advance Bresenham one step

    // Primitive types
    localparam [1:0]
        PRIM_LINE = 2'd0,
        PRIM_TRI  = 2'd1;

    // =========================================================================
    // Latched configuration
    // =========================================================================
    reg [1:0]  cfg_prim_type;
    reg [31:0] cfg_prim_base;
    reg [31:0] cfg_prim_count;
    reg [23:0] cfg_color;
    reg [31:0] cfg_fb_base;
    reg [31:0] cfg_fb_stride;

    // =========================================================================
    // Vertex buffer (6 words × 32 bits = up to 3 vertices)
    // =========================================================================
    reg [31:0] vbuf [0:5];
    reg [2:0]  vbuf_wptr;   // write pointer (0..5)

    // Unpacked signed vertex coordinates
    reg signed [31:0] vx [0:2];
    reg signed [31:0] vy [0:2];

    // =========================================================================
    // Bresenham engine registers
    // =========================================================================
    reg signed [31:0] b_cx;    // current X
    reg signed [31:0] b_cy;    // current Y
    reg signed [31:0] b_ex;    // end X
    reg signed [31:0] b_ey;    // end Y
    reg signed [31:0] b_dx;    // abs(dx)
    reg signed [31:0] b_dy;    // abs(dy)
    reg signed [31:0] b_err;   // error term
    reg               b_sx;    // x step direction: 1 = +1, 0 = -1
    reg               b_sy;    // y step direction: 1 = +1, 0 = -1
    reg               b_steep; // 1 = iterate over Y axis

    // =========================================================================
    // Segment tracking
    // =========================================================================
    reg [1:0] seg_cur;    // current segment index (0, 1, 2)
    reg [1:0] seg_max;    // total segments to draw (1 or 3)

    // =========================================================================
    // Pixel address helper (combinatorial)
    // =========================================================================
    // Computed each cycle from current Bresenham position
    wire [31:0] cur_pixel_addr;
    assign cur_pixel_addr = cfg_fb_base
                          + (b_cy[31:0] * cfg_fb_stride)
                          + {b_cx[29:0], 2'b00};   // b_cx * 4

    wire [31:0] cur_pixel_data;
    assign cur_pixel_data = {8'h00, cfg_color};

    // =========================================================================
    // Top-level state and raster sub-state
    // =========================================================================
    reg [2:0] state;
    reg [1:0] rast_sub;

    // =========================================================================
    // Utility: segment start/end selection (combinatorial)
    // =========================================================================
    //   seg 0: v0 → v1
    //   seg 1: v1 → v2
    //   seg 2: v0 → v2
    reg signed [31:0] seg_sx, seg_sy, seg_ex, seg_ey;
    always @(*) begin
        case (seg_cur)
            2'd0: begin
                seg_sx = vx[0]; seg_sy = vy[0];
                seg_ex = vx[1]; seg_ey = vy[1];
            end
            2'd1: begin
                seg_sx = vx[1]; seg_sy = vy[1];
                seg_ex = vx[2]; seg_ey = vy[2];
            end
            2'd2: begin
                seg_sx = vx[0]; seg_sy = vy[0];
                seg_ex = vx[2]; seg_ey = vy[2];
            end
            default: begin
                seg_sx = vx[0]; seg_sy = vy[0];
                seg_ex = vx[1]; seg_ey = vy[1];
            end
        endcase
    end

    // =========================================================================
    // Bresenham init helper — combinatorial wires computed from current segment
    // endpoints.  These are sampled inside RS_INIT via non-blocking assignments.
    // =========================================================================
    wire signed [31:0] bi_raw_dx = seg_ex - seg_sx;
    wire signed [31:0] bi_raw_dy = seg_ey - seg_sy;
    wire signed [31:0] bi_abs_dx = bi_raw_dx[31] ? (-bi_raw_dx) : bi_raw_dx;
    wire signed [31:0] bi_abs_dy = bi_raw_dy[31] ? (-bi_raw_dy) : bi_raw_dy;
    wire               bi_steep  = (bi_abs_dy > bi_abs_dx);
    wire signed [31:0] bi_err    = bi_steep
                                  ? ((bi_abs_dx << 1) - bi_abs_dy)
                                  : ((bi_abs_dy << 1) - bi_abs_dx);

    // =========================================================================
    // Main synchronous process
    // =========================================================================
    always @(posedge clk) begin : main_fsm

        // Per-cycle defaults for one-cycle pulses
        ar_rm_start       <= 1'b0;
        ar_done           <= 1'b0;
        ar_error          <= 1'b0;

        // ---- Global reset / ar_reset -----------------------------------------
        if (rst || ar_reset) begin
            state             <= ST_IDLE;
            rast_sub          <= RS_INIT;
            ar_busy           <= 1'b0;
            ar_wm_pixel_valid <= 1'b0;
            ar_rm_base_addr   <= 32'd0;
            ar_rm_beat_count  <= 16'd0;
            ar_wm_pixel_data  <= 32'd0;
            ar_wm_pixel_addr  <= 32'd0;
            vbuf_wptr         <= 3'd0;
            seg_cur           <= 2'd0;
            seg_max           <= 2'd1;
            vbuf[0] <= 32'd0; vbuf[1] <= 32'd0;
            vbuf[2] <= 32'd0; vbuf[3] <= 32'd0;
            vbuf[4] <= 32'd0; vbuf[5] <= 32'd0;

        end else begin

            case (state)

                // =============================================================
                // IDLE — wait for ar_start
                // =============================================================
                ST_IDLE: begin
                    ar_busy           <= 1'b0;
                    ar_wm_pixel_valid <= 1'b0;
                    vbuf_wptr         <= 3'd0;

                    if (ar_start) begin
                        // Latch all control inputs
                        cfg_prim_type  <= ar_prim_type;
                        cfg_prim_base  <= ar_prim_base;
                        cfg_prim_count <= ar_prim_count;
                        cfg_color      <= ar_color;
                        cfg_fb_base    <= ar_fb_base;
                        cfg_fb_stride  <= ar_fb_stride;

                        ar_busy <= 1'b1;
                        state   <= ST_FETCH;
                    end
                end

                // =============================================================
                // FETCH — buffer vertex words while they arrive; wait for done
                // =============================================================
                ST_FETCH: begin
                    // Accumulate vertex words into buffer
                    if (ar_rm_rvalid && (vbuf_wptr < 3'd6)) begin
                        vbuf[vbuf_wptr] <= ar_rm_rdata;
                        vbuf_wptr       <= vbuf_wptr + 3'd1;
                    end

                    // Issue the read-master start pulse on the first cycle
                    // We detect "first cycle" by: not busy, not done, and wptr==0
                    if (!ar_rm_busy && !ar_rm_done && (vbuf_wptr == 3'd0)) begin
                        ar_rm_base_addr  <= cfg_prim_base;
                        // beat_count: use prim_count if > 0, else derive from type
                        ar_rm_beat_count <= (cfg_prim_count[15:0] != 16'd0)
                                          ? cfg_prim_count[15:0]
                                          : (cfg_prim_type == PRIM_TRI)
                                            ? 16'd3 : 16'd2;
                        ar_rm_start      <= 1'b1;
                    end

                    if (ar_rm_done) begin
                        // Unpack vertex buffer into signed coordinates
                        // Format: vbuf[n][31:16] = Y, vbuf[n][15:0] = X
                        vx[0] <= {{16{vbuf[0][15]}}, vbuf[0][15:0]};
                        vy[0] <= {{16{vbuf[0][31]}}, vbuf[0][31:16]};
                        vx[1] <= {{16{vbuf[1][15]}}, vbuf[1][15:0]};
                        vy[1] <= {{16{vbuf[1][31]}}, vbuf[1][31:16]};
                        vx[2] <= {{16{vbuf[2][15]}}, vbuf[2][15:0]};
                        vy[2] <= {{16{vbuf[2][31]}}, vbuf[2][31:16]};

                        // Set up segment tracking
                        seg_cur <= 2'd0;
                        seg_max <= (cfg_prim_type == PRIM_TRI) ? 2'd3 : 2'd1;
                        rast_sub <= RS_INIT;

                        state <= ST_RAST;
                    end
                end

                // =============================================================
                // RAST — Bresenham line rasteriser
                // =============================================================
                ST_RAST: begin
                    case (rast_sub)

                        // ---- Initialise Bresenham for current segment ----------
                        RS_INIT: begin
                            // seg_sx/sy/ex/ey and bi_* are purely combinatorial
                            // wires driven by seg_cur; capture them via non-blocking
                            // assignments so the always block stays hazard-free.
                            b_cx    <= seg_sx;
                            b_cy    <= seg_sy;
                            b_ex    <= seg_ex;
                            b_ey    <= seg_ey;
                            b_dx    <= bi_abs_dx;
                            b_dy    <= bi_abs_dy;
                            b_sx    <= ~bi_raw_dx[31];  // 1 = step right, 0 = step left
                            b_sy    <= ~bi_raw_dy[31];  // 1 = step down,  0 = step up
                            b_steep <= bi_steep;
                            b_err   <= bi_err;

                            ar_wm_pixel_valid <= 1'b0;
                            rast_sub          <= RS_PIXEL;
                        end

                        // ---- Present current pixel to write master ------------
                        RS_PIXEL: begin
                            ar_wm_pixel_data  <= cur_pixel_data;
                            ar_wm_pixel_addr  <= cur_pixel_addr;
                            ar_wm_pixel_valid <= 1'b1;
                            rast_sub          <= RS_STEP;
                        end

                        // ---- Wait for pixel_ready, then advance or finish ------
                        RS_STEP: begin
                            if (ar_wm_pixel_ready) begin
                                ar_wm_pixel_valid <= 1'b0;

                                // Check for end-of-segment
                                if ((b_cx == b_ex) && (b_cy == b_ey)) begin
                                    // End of this segment
                                    if (seg_cur == (seg_max - 2'd1)) begin
                                        // All segments complete
                                        state    <= ST_DONE;
                                    end else begin
                                        // Advance to next segment
                                        seg_cur  <= seg_cur + 2'd1;
                                        rast_sub <= RS_INIT;
                                    end
                                end else begin
                                    // ---- Bresenham step ----
                                    if (!b_steep) begin
                                        // Shallow: primary axis is X
                                        b_cx  <= b_cx + (b_sx ? 32'sd1 : -32'sd1);
                                        if (b_err >= 0) begin
                                            b_cy  <= b_cy + (b_sy ? 32'sd1 : -32'sd1);
                                            b_err <= b_err + (b_dy << 1) - (b_dx << 1);
                                        end else begin
                                            b_err <= b_err + (b_dy << 1);
                                        end
                                    end else begin
                                        // Steep: primary axis is Y
                                        b_cy  <= b_cy + (b_sy ? 32'sd1 : -32'sd1);
                                        if (b_err >= 0) begin
                                            b_cx  <= b_cx + (b_sx ? 32'sd1 : -32'sd1);
                                            b_err <= b_err + (b_dx << 1) - (b_dy << 1);
                                        end else begin
                                            b_err <= b_err + (b_dx << 1);
                                        end
                                    end
                                    rast_sub <= RS_PIXEL;
                                end
                            end
                            // else: stall — keep ar_wm_pixel_valid high, wait
                        end

                        default: rast_sub <= RS_INIT;

                    endcase
                end

                // =============================================================
                // DONE — assert ar_done for one cycle
                // =============================================================
                ST_DONE: begin
                    ar_done  <= 1'b1;
                    ar_busy  <= 1'b0;
                    state    <= ST_IDLE;
                end

                // =============================================================
                // ERROR — assert ar_error for one cycle
                // =============================================================
                ST_ERROR: begin
                    ar_error <= 1'b1;
                    ar_busy  <= 1'b0;
                    state    <= ST_IDLE;
                end

                default: state <= ST_IDLE;

            endcase
        end
    end

endmodule

`default_nettype wire
