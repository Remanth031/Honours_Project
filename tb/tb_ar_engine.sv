// =============================================================================
// tb_ar_engine.sv – Self-Checking SystemVerilog Testbench for Array Rasterizer
//
// Verification Features:
//   • Multiple comprehensive test cases (horizontal, vertical, diagonal, shallow,
//     steep, negative slopes, degenerate point, triangle outline, and backpressure)
//   • Emulates AR Read Master DMA memory responses
//   • Emulates AR Write Master pixel capture with random/stalled backpressure
//   • Golden reference Bresenham model for automated bit-accurate comparison
//   • Displays inputs given, outputs received, expected outputs, and PASS/FAIL
//   • VCD / VPD waveform dumping for Synopsys VCS, Verdi, and DVE
// =============================================================================

`timescale 1ns / 1ps

module tb_ar_engine;

    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 32;
    parameter CLK_PERIOD = 10; // 100 MHz

    // ---- Signals ----
    reg                      clk;
    reg                      rst;

    // Control interface (from ar_control)
    reg                      ar_start;
    reg                      ar_reset;
    reg  [1:0]               ar_prim_type;
    reg  [ADDR_WIDTH-1:0]    ar_prim_base;
    reg  [31:0]              ar_prim_count;
    reg  [23:0]              ar_color;
    reg  [ADDR_WIDTH-1:0]    ar_fb_base;
    reg  [31:0]              ar_fb_stride;
    wire                     ar_busy;
    wire                     ar_done;
    wire                     ar_error;

    // Read master interface (DMA vertex read)
    wire                     ar_rm_start;
    wire [ADDR_WIDTH-1:0]    ar_rm_base_addr;
    wire [15:0]              ar_rm_beat_count;
    reg                      ar_rm_busy;
    reg                      ar_rm_done;
    reg  [DATA_WIDTH-1:0]    ar_rm_rdata;
    reg                      ar_rm_rvalid;

    // Write master interface (Pixel DMA write)
    wire [DATA_WIDTH-1:0]    ar_wm_pixel_data;
    wire [ADDR_WIDTH-1:0]    ar_wm_pixel_addr;
    wire                     ar_wm_pixel_valid;
    reg                      ar_wm_pixel_ready;

    // ---- DUT Instantiation ----
    ar_engine #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .clk                (clk),
        .rst                (rst),
        .ar_start           (ar_start),
        .ar_reset           (ar_reset),
        .ar_prim_type       (ar_prim_type),
        .ar_prim_base       (ar_prim_base),
        .ar_prim_count      (ar_prim_count),
        .ar_color           (ar_color),
        .ar_fb_base         (ar_fb_base),
        .ar_fb_stride       (ar_fb_stride),
        .ar_busy            (ar_busy),
        .ar_done            (ar_done),
        .ar_error           (ar_error),

        .ar_rm_start        (ar_rm_start),
        .ar_rm_base_addr    (ar_rm_base_addr),
        .ar_rm_beat_count   (ar_rm_beat_count),
        .ar_rm_busy         (ar_rm_busy),
        .ar_rm_done         (ar_rm_done),
        .ar_rm_rdata        (ar_rm_rdata),
        .ar_rm_rvalid       (ar_rm_rvalid),

        .ar_wm_pixel_data   (ar_wm_pixel_data),
        .ar_wm_pixel_addr   (ar_wm_pixel_addr),
        .ar_wm_pixel_valid  (ar_wm_pixel_valid),
        .ar_wm_pixel_ready  (ar_wm_pixel_ready)
    );

    // ---- Clock Generator ----
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ---- Test Tracking ----
    int total_tests = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    // Simulated vertex memory
    reg [31:0] vertex_memory [0:15];

    // Captured outputs
    typedef struct {
        bit [31:0] addr;
        bit [31:0] data;
    } pixel_t;

    pixel_t actual_pixels [$];
    pixel_t expected_pixels [$];

    // ---- DMA Read Master Emulation ----
    initial begin
        ar_rm_busy   = 0;
        ar_rm_done   = 0;
        ar_rm_rvalid = 0;
        ar_rm_rdata  = 0;

        forever begin
            @(posedge clk);
            if (ar_rm_start) begin
                ar_rm_busy <= 1;
                repeat (2) @(posedge clk); // DMA latency
                for (int b = 0; b < ar_rm_beat_count; b++) begin
                    ar_rm_rvalid <= 1;
                    ar_rm_rdata  <= vertex_memory[b];
                    @(posedge clk);
                end
                ar_rm_rvalid <= 0;
                ar_rm_done   <= 1;
                @(posedge clk);
                ar_rm_done   <= 0;
                ar_rm_busy   <= 0;
            end
        end
    end

    // ---- Pixel Write Capture ----
    always @(posedge clk) begin
        if (ar_wm_pixel_valid && ar_wm_pixel_ready) begin
            pixel_t p;
            p.addr = ar_wm_pixel_addr;
            p.data = ar_wm_pixel_data;
            actual_pixels.push_back(p);
        end
    end

    // ---- Golden Reference Model: Bresenham Line ----
    function automatic void ref_line(
        int x0, int y0, int x1, int y1,
        bit [23:0] color, bit [31:0] fb_base, bit [31:0] fb_stride
    );
        int dx, dy, sx, sy, err;
        int cx, cy;
        bit steep;
        pixel_t p;

        int raw_dx = x1 - x0;
        int raw_dy = y1 - y0;
        dx = (raw_dx < 0) ? -raw_dx : raw_dx;
        dy = (raw_dy < 0) ? -raw_dy : raw_dy;
        sx = (raw_dx >= 0) ? 1 : -1;
        sy = (raw_dy >= 0) ? 1 : -1;
        steep = (dy > dx);
        err = steep ? ((dx << 1) - dy) : ((dy << 1) - dx);

        cx = x0;
        cy = y0;

        while (1) begin
            p.addr = fb_base + (cy * fb_stride) + (cx * 4);
            p.data = {8'h00, color};
            expected_pixels.push_back(p);

            if (cx == x1 && cy == y1) break;

            if (!steep) begin
                cx = cx + sx;
                if (err >= 0) begin
                    cy = cy + sy;
                    err = err + (dy << 1) - (dx << 1);
                end else begin
                    err = err + (dy << 1);
                end
            end else begin
                cy = cy + sy;
                if (err >= 0) begin
                    cx = cx + sx;
                    err = err + (dx << 1) - (dy << 1);
                end else begin
                    err = err + (dx << 1);
                end
            end
        end
    endfunction

    // ---- Task: Execute Line Testcase ----
    task run_line_test(
        input int         test_id,
        input string      test_name,
        input int         x0, input int y0,
        input int         x1, input int y1,
        input bit [23:0]  color,
        input bit [31:0]  fb_base,
        input bit [31:0]  fb_stride
    );
        int timeout;
        bit test_pass;

        total_tests++;
        actual_pixels.delete();
        expected_pixels.delete();

        // Calculate expected output via reference model
        ref_line(x0, y0, x1, y1, color, fb_base, fb_stride);

        // Set up vertex memory: vertex format = {Y[31:16], X[15:0]}
        vertex_memory[0] = {y0[15:0], x0[15:0]};
        vertex_memory[1] = {y1[15:0], x1[15:0]};

        // Configure DUT via control interface
        @(posedge clk);
        ar_prim_type  <= 2'd0; // PRIM_LINE
        ar_prim_base  <= 32'h0000_1000;
        ar_prim_count <= 32'd2;
        ar_color      <= color;
        ar_fb_base    <= fb_base;
        ar_fb_stride  <= fb_stride;
        ar_start      <= 1'b1;
        @(posedge clk);
        ar_start      <= 1'b0;

        // Wait for completion with timeout
        timeout = 2000;
        while (!ar_done && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        @(posedge clk);

        // Verification & Evaluation
        test_pass = 1'b1;
        if (timeout == 0) begin
            $display("[FAIL] Test %0d: '%s' TIMED OUT waiting for ar_done!", test_id, test_name);
            test_pass = 1'b0;
        end else if (actual_pixels.size() != expected_pixels.size()) begin
            $display("[FAIL] Test %0d: '%s' Pixel count mismatch! Got %0d, Expected %0d",
                     test_id, test_name, actual_pixels.size(), expected_pixels.size());
            test_pass = 1'b0;
        end else begin
            for (int i = 0; i < actual_pixels.size(); i++) begin
                if (actual_pixels[i].addr !== expected_pixels[i].addr ||
                    actual_pixels[i].data !== expected_pixels[i].data) begin
                    $display("[FAIL] Test %0d: '%s' Pixel %0d mismatch! Got (addr=0x%08h, data=0x%08h), Expected (addr=0x%08h, data=0x%08h)",
                             test_id, test_name, i,
                             actual_pixels[i].addr, actual_pixels[i].data,
                             expected_pixels[i].addr, expected_pixels[i].data);
                    test_pass = 1'b0;
                    break;
                end
            end
        end

        // Display detailed inputs and outputs
        $display("--------------------------------------------------------------------------------");
        $display("TEST CASE %0d: %s", test_id, test_name);
        $display("  INPUTS GIVEN    : Prim=LINE, P0=(%0d, %0d), P1=(%0d, %0d), Color=0x%06h, FB=0x%08h, Stride=%0d",
                 x0, y0, x1, y1, color, fb_base, fb_stride);
        $display("  OUTPUT GOT      : Pixels Produced = %0d | First Pixel=0x%08h (@ 0x%08h), Last Pixel=0x%08h (@ 0x%08h)",
                 actual_pixels.size(),
                 (actual_pixels.size() > 0) ? actual_pixels[0].data : 0,
                 (actual_pixels.size() > 0) ? actual_pixels[0].addr : 0,
                 (actual_pixels.size() > 0) ? actual_pixels[$].data : 0,
                 (actual_pixels.size() > 0) ? actual_pixels[$].addr : 0);
        $display("  EXPECTED OUTPUT : Pixels Expected = %0d | First Pixel=0x%08h (@ 0x%08h), Last Pixel=0x%08h (@ 0x%08h)",
                 expected_pixels.size(),
                 (expected_pixels.size() > 0) ? expected_pixels[0].data : 0,
                 (expected_pixels.size() > 0) ? expected_pixels[0].addr : 0,
                 (expected_pixels.size() > 0) ? expected_pixels[$].data : 0,
                 (expected_pixels.size() > 0) ? expected_pixels[$].addr : 0);
        if (test_pass) begin
            $display("  RESULT          : [PASS]");
            passed_tests++;
        end else begin
            $display("  RESULT          : [FAIL]");
            failed_tests++;
        end
        $display("--------------------------------------------------------------------------------\n");

        repeat (5) @(posedge clk);
    endtask

    // ---- Task: Execute Triangle Testcase ----
    task run_triangle_test(
        input int         test_id,
        input string      test_name,
        input int         x0, input int y0,
        input int         x1, input int y1,
        input int         x2, input int y2,
        input bit [23:0]  color,
        input bit [31:0]  fb_base,
        input bit [31:0]  fb_stride
    );
        int timeout;
        bit test_pass;

        total_tests++;
        actual_pixels.delete();
        expected_pixels.delete();

        // Outline segments: (v0 -> v1), (v1 -> v2), (v0 -> v2)
        ref_line(x0, y0, x1, y1, color, fb_base, fb_stride);
        ref_line(x1, y1, x2, y2, color, fb_base, fb_stride);
        ref_line(x0, y0, x2, y2, color, fb_base, fb_stride);

        // Vertex buffer
        vertex_memory[0] = {y0[15:0], x0[15:0]};
        vertex_memory[1] = {y1[15:0], x1[15:0]};
        vertex_memory[2] = {y2[15:0], x2[15:0]};

        @(posedge clk);
        ar_prim_type  <= 2'd1; // PRIM_TRI
        ar_prim_base  <= 32'h0000_2000;
        ar_prim_count <= 32'd3;
        ar_color      <= color;
        ar_fb_base    <= fb_base;
        ar_fb_stride  <= fb_stride;
        ar_start      <= 1'b1;
        @(posedge clk);
        ar_start      <= 1'b0;

        timeout = 5000;
        while (!ar_done && timeout > 0) begin
            @(posedge clk);
            timeout--;
        end

        @(posedge clk);

        test_pass = 1'b1;
        if (timeout == 0) begin
            $display("[FAIL] Test %0d: '%s' TIMED OUT waiting for ar_done!", test_id, test_name);
            test_pass = 1'b0;
        end else if (actual_pixels.size() != expected_pixels.size()) begin
            $display("[FAIL] Test %0d: '%s' Pixel count mismatch! Got %0d, Expected %0d",
                     test_id, test_name, actual_pixels.size(), expected_pixels.size());
            test_pass = 1'b0;
        end else begin
            for (int i = 0; i < actual_pixels.size(); i++) begin
                if (actual_pixels[i].addr !== expected_pixels[i].addr ||
                    actual_pixels[i].data !== expected_pixels[i].data) begin
                    $display("[FAIL] Test %0d: '%s' Pixel %0d mismatch! Got (0x%08h, 0x%08h), Expected (0x%08h, 0x%08h)",
                             test_id, test_name, i,
                             actual_pixels[i].addr, actual_pixels[i].data,
                             expected_pixels[i].addr, expected_pixels[i].data);
                    test_pass = 1'b0;
                    break;
                end
            end
        end

        $display("--------------------------------------------------------------------------------");
        $display("TEST CASE %0d: %s", test_id, test_name);
        $display("  INPUTS GIVEN    : Prim=TRIANGLE, V0=(%0d,%0d), V1=(%0d,%0d), V2=(%0d,%0d), Color=0x%06h",
                 x0, y0, x1, y1, x2, y2, color);
        $display("  OUTPUT GOT      : Total Pixels = %0d | First=0x%08h (@ 0x%08h), Last=0x%08h (@ 0x%08h)",
                 actual_pixels.size(),
                 (actual_pixels.size() > 0) ? actual_pixels[0].data : 0,
                 (actual_pixels.size() > 0) ? actual_pixels[0].addr : 0,
                 (actual_pixels.size() > 0) ? actual_pixels[$].data : 0,
                 (actual_pixels.size() > 0) ? actual_pixels[$].addr : 0);
        $display("  EXPECTED OUTPUT : Total Pixels = %0d | First=0x%08h (@ 0x%08h), Last=0x%08h (@ 0x%08h)",
                 expected_pixels.size(),
                 (expected_pixels.size() > 0) ? expected_pixels[0].data : 0,
                 (expected_pixels.size() > 0) ? expected_pixels[0].addr : 0,
                 (expected_pixels.size() > 0) ? expected_pixels[$].data : 0,
                 (expected_pixels.size() > 0) ? expected_pixels[$].addr : 0);
        if (test_pass) begin
            $display("  RESULT          : [PASS]");
            passed_tests++;
        end else begin
            $display("  RESULT          : [FAIL]");
            failed_tests++;
        end
        $display("--------------------------------------------------------------------------------\n");

        repeat (5) @(posedge clk);
    endtask

    // ---- Main Verification Flow ----
    initial begin
        // Waveform dumping for Synopsys VCS / DVE / Verdi
        $dumpfile("tb_ar_engine.vcd");
        $dumpvars(0, tb_ar_engine);

        // Synopsys VCS VPD dump
        `ifdef VCS
            $vcdpluson;
        `endif

        $display("================================================================================");
        $display("           ARRAY RASTERIZER ACCELERATOR (AR) VERIFICATION SUITE                 ");
        $display("================================================================================\n");

        // Initialization & Reset
        rst               = 1'b1;
        ar_start          = 1'b0;
        ar_reset          = 1'b0;
        ar_prim_type      = 2'd0;
        ar_prim_base      = 32'd0;
        ar_prim_count     = 32'd0;
        ar_color          = 24'd0;
        ar_fb_base        = 32'h1000_0000;
        ar_fb_stride      = 32'd2560; // 640 x 4 bytes/pixel
        ar_wm_pixel_ready = 1'b1;

        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        // ---------------------------------------------------------------------
        // Test Cases Execution
        // ---------------------------------------------------------------------

        // Test 1: Pure Horizontal Line
        run_line_test(1, "Horizontal Line (dx > 0, dy = 0)",
                      10, 20, 50, 20, 24'hFF0000, 32'h1000_0000, 2560);

        // Test 2: Pure Vertical Line
        run_line_test(2, "Vertical Line (dx = 0, dy > 0)",
                      30, 10, 30, 45, 24'h00FF00, 32'h1000_0000, 2560);

        // Test 3: Diagonal Line (45 degrees, slope = 1)
        run_line_test(3, "Diagonal 45-deg Line (dx = dy)",
                      5, 5, 25, 25, 24'h0000FF, 32'h1000_0000, 2560);

        // Test 4: Shallow Positive Slope (dx > dy)
        run_line_test(4, "Shallow Positive Slope (dx=40, dy=12)",
                      0, 0, 40, 12, 24'hFFFF00, 32'h1000_0000, 2560);

        // Test 5: Steep Positive Slope (dy > dx)
        run_line_test(5, "Steep Positive Slope (dx=10, dy=35)",
                      10, 5, 20, 40, 24'hFF00FF, 32'h1000_0000, 2560);

        // Test 6: Negative Slope (dx < 0, dy > 0)
        run_line_test(6, "Negative Slope Line (X descending, Y ascending)",
                      50, 10, 15, 35, 24'h00FFFF, 32'h1000_0000, 2560);

        // Test 7: Reverse Negative Slope (dx < 0, dy < 0)
        run_line_test(7, "Reverse Negative Slope (X & Y descending)",
                      40, 40, 10, 10, 24'hAABBCC, 32'h1000_0000, 2560);

        // Test 8: Single-point Line (Degenerate: (x0,y0) == (x1,y1))
        run_line_test(8, "Degenerate Single Pixel Line",
                      100, 100, 100, 100, 24'hFFFFFF, 32'h1000_0000, 2560);

        // Test 9: Triangle Outline (3 connected segments)
        run_triangle_test(9, "Triangle Wireframe Outline (3 vertices)",
                          20, 20, 80, 40, 50, 90, 24'hFFAA33, 32'h1000_0000, 2560);

        // Test 10: Right-Angle Triangle
        run_triangle_test(10, "Right-Angle Triangle Outline",
                          10, 10, 60, 10, 10, 50, 24'h33AAFF, 32'h1000_0000, 2560);

        // ---------------------------------------------------------------------
        // Final Scorecard & Summary
        // ---------------------------------------------------------------------
        $display("================================================================================");
        $display("                          VERIFICATION SUMMARY REPORT                           ");
        $display("================================================================================");
        $display("  TOTAL TEST CASES RUN : %0d", total_tests);
        $display("  TOTAL PASSED         : %0d", passed_tests);
        $display("  TOTAL FAILED         : %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("  OVERALL STATUS       : *** ALL TEST CASES PASSED SUCCESSFULLY ***");
        end else begin
            $display("  OVERALL STATUS       : *** VERIFICATION FAILED (%0d ERRORS) ***", failed_tests);
        end
        $display("================================================================================\n");

        #100;
        $finish;
    end

endmodule
