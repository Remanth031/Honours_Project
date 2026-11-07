// =============================================================================
// verify_ar_engine.cpp – Cycle-Accurate Verification Suite (125 Testcases)
//
// Features:
//   • 125 exhaustive testcases across 8 test categories
//   • Bit-accurate comparison against golden Bresenham reference model
//   • Displays inputs given, outputs received, expected outputs, and pass/fail
//   • Generates tb_ar_engine.vcd for Synopsys VCS, Verdi, and DVE
// =============================================================================

#include <iostream>
#include <iomanip>
#include <vector>
#include <string>
#include <cstdint>
#include <fstream>
#include <sstream>
#include <bitset>

using namespace std;

struct Pixel {
    uint32_t addr;
    uint32_t data;
};

// Golden Reference Model
vector<Pixel> golden_line(int32_t x0, int32_t y0, int32_t x1, int32_t y1,
                          uint32_t color, uint32_t fb_base, uint32_t fb_stride) {
    vector<Pixel> pixels;
    int32_t raw_dx = x1 - x0;
    int32_t raw_dy = y1 - y0;
    int32_t dx = (raw_dx < 0) ? -raw_dx : raw_dx;
    int32_t dy = (raw_dy < 0) ? -raw_dy : raw_dy;
    bool sx = (raw_dx >= 0);
    bool sy = (raw_dy >= 0);
    bool steep = (dy > dx);
    int32_t err = steep ? ((dx << 1) - dy) : ((dy << 1) - dx);

    int32_t cx = x0;
    int32_t cy = y0;

    while (true) {
        Pixel p;
        p.addr = fb_base + (cy * fb_stride) + (cx * 4);
        p.data = color & 0x00FFFFFF;
        pixels.push_back(p);

        if (cx == x1 && cy == y1) break;

        if (!steep) {
            cx += (sx ? 1 : -1);
            if (err >= 0) {
                cy += (sy ? 1 : -1);
                err += (dy << 1) - (dx << 1);
            } else {
                err += (dy << 1);
            }
        } else {
            cy += (sy ? 1 : -1);
            if (err >= 0) {
                cx += (sx ? 1 : -1);
                err += (dx << 1) - (dy << 1);
            } else {
                err += (dx << 1);
            }
        }
    }
    return pixels;
}

// RTL Cycle-Accurate Simulator for ar_engine
class AREngineDUT {
public:
    enum State { ST_IDLE = 0, ST_FETCH = 1, ST_RAST = 2, ST_DONE = 3, ST_ERROR = 4 };
    enum RastSub { RS_INIT = 0, RS_PIXEL = 1, RS_STEP = 2 };

    State state = ST_IDLE;
    RastSub rast_sub = RS_INIT;

    uint32_t cfg_prim_type = 0;
    uint32_t cfg_prim_base = 0;
    uint32_t cfg_prim_count = 0;
    uint32_t cfg_color = 0;
    uint32_t cfg_fb_base = 0;
    uint32_t cfg_fb_stride = 0;

    uint32_t vbuf[6] = {0};
    uint32_t vbuf_wptr = 0;

    int32_t vx[3] = {0};
    int32_t vy[3] = {0};

    int32_t b_cx = 0, b_cy = 0, b_ex = 0, b_ey = 0;
    int32_t b_dx = 0, b_dy = 0, b_err = 0;
    bool b_sx = false, b_sy = false, b_steep = false;

    uint32_t seg_cur = 0;
    uint32_t seg_max = 1;
    bool rm_started = false;

    bool ar_busy = false;
    bool ar_done = false;
    bool ar_error = false;

    bool ar_rm_start = false;
    uint32_t ar_rm_base_addr = 0;
    uint16_t ar_rm_beat_count = 0;

    uint32_t ar_wm_pixel_data = 0;
    uint32_t ar_wm_pixel_addr = 0;
    bool ar_wm_pixel_valid = false;

    void reset() {
        state = ST_IDLE;
        rast_sub = RS_INIT;
        ar_busy = false;
        ar_done = false;
        ar_error = false;
        ar_wm_pixel_valid = false;
        vbuf_wptr = 0;
        seg_cur = 0;
        seg_max = 1;
        rm_started = false;
    }

    void clock_step(bool ar_start, uint32_t prim_type, uint32_t prim_base, uint32_t prim_count,
                    uint32_t color, uint32_t fb_base, uint32_t fb_stride,
                    bool ar_rm_done, bool ar_rm_rvalid, uint32_t ar_rm_rdata,
                    bool ar_wm_pixel_ready) {
        ar_rm_start = false;
        ar_done = false;
        ar_error = false;

        switch (state) {
            case ST_IDLE:
                ar_busy = false;
                ar_wm_pixel_valid = false;
                vbuf_wptr = 0;
                rm_started = false;
                if (ar_start) {
                    cfg_prim_type  = prim_type;
                    cfg_prim_base  = prim_base;
                    cfg_prim_count = prim_count;
                    cfg_color      = color;
                    cfg_fb_base    = fb_base;
                    cfg_fb_stride  = fb_stride;
                    ar_busy = true;
                    state = ST_FETCH;
                }
                break;

            case ST_FETCH:
                if (ar_rm_rvalid && vbuf_wptr < 6) {
                    vbuf[vbuf_wptr++] = ar_rm_rdata;
                }
                if (!rm_started) {
                    ar_rm_base_addr = cfg_prim_base;
                    ar_rm_beat_count = (cfg_prim_count != 0) ? cfg_prim_count : ((cfg_prim_type == 1) ? 3 : 2);
                    ar_rm_start = true;
                    rm_started = true;
                }
                if (ar_rm_done) {
                    vx[0] = (int16_t)(vbuf[0] & 0xFFFF);
                    vy[0] = (int16_t)((vbuf[0] >> 16) & 0xFFFF);
                    vx[1] = (int16_t)(vbuf[1] & 0xFFFF);
                    vy[1] = (int16_t)((vbuf[1] >> 16) & 0xFFFF);
                    vx[2] = (int16_t)(vbuf[2] & 0xFFFF);
                    vy[2] = (int16_t)((vbuf[2] >> 16) & 0xFFFF);

                    seg_cur = 0;
                    seg_max = (cfg_prim_type == 1) ? 3 : 1;
                    rast_sub = RS_INIT;
                    state = ST_RAST;
                }
                break;

            case ST_RAST: {
                int32_t seg_sx = 0, seg_sy = 0, seg_ex = 0, seg_ey = 0;
                if (seg_cur == 0) { seg_sx = vx[0]; seg_sy = vy[0]; seg_ex = vx[1]; seg_ey = vy[1]; }
                else if (seg_cur == 1) { seg_sx = vx[1]; seg_sy = vy[1]; seg_ex = vx[2]; seg_ey = vy[2]; }
                else { seg_sx = vx[0]; seg_sy = vy[0]; seg_ex = vx[2]; seg_ey = vy[2]; }

                int32_t bi_raw_dx = seg_ex - seg_sx;
                int32_t bi_raw_dy = seg_ey - seg_sy;
                int32_t bi_abs_dx = (bi_raw_dx < 0) ? -bi_raw_dx : bi_raw_dx;
                int32_t bi_abs_dy = (bi_raw_dy < 0) ? -bi_raw_dy : bi_raw_dy;
                bool bi_steep = (bi_abs_dy > bi_abs_dx);
                int32_t bi_err = bi_steep ? ((bi_abs_dx << 1) - bi_abs_dy) : ((bi_abs_dy << 1) - bi_abs_dx);

                if (rast_sub == RS_INIT) {
                    b_cx = seg_sx; b_cy = seg_sy;
                    b_ex = seg_ex; b_ey = seg_ey;
                    b_dx = bi_abs_dx; b_dy = bi_abs_dy;
                    b_sx = (bi_raw_dx >= 0);
                    b_sy = (bi_raw_dy >= 0);
                    b_steep = bi_steep;
                    b_err = bi_err;
                    ar_wm_pixel_valid = false;
                    rast_sub = RS_PIXEL;
                } else if (rast_sub == RS_PIXEL) {
                    ar_wm_pixel_data = cfg_color & 0x00FFFFFF;
                    ar_wm_pixel_addr = cfg_fb_base + (b_cy * cfg_fb_stride) + (b_cx * 4);
                    ar_wm_pixel_valid = true;
                    rast_sub = RS_STEP;
                } else if (rast_sub == RS_STEP) {
                    if (ar_wm_pixel_ready) {
                        ar_wm_pixel_valid = false;
                        if (b_cx == b_ex && b_cy == b_ey) {
                            if (seg_cur == seg_max - 1) {
                                state = ST_DONE;
                            } else {
                                seg_cur++;
                                rast_sub = RS_INIT;
                            }
                        } else {
                            if (!b_steep) {
                                b_cx += (b_sx ? 1 : -1);
                                if (b_err >= 0) {
                                    b_cy += (b_sy ? 1 : -1);
                                    b_err += (b_dy << 1) - (b_dx << 1);
                                } else {
                                    b_err += (b_dy << 1);
                                }
                            } else {
                                b_cy += (b_sy ? 1 : -1);
                                if (b_err >= 0) {
                                    b_cx += (b_sx ? 1 : -1);
                                    b_err += (b_dx << 1) - (b_dy << 1);
                                } else {
                                    b_err += (b_dx << 1);
                                }
                            }
                            rast_sub = RS_PIXEL;
                        }
                    }
                }
                break;
            }

            case ST_DONE:
                ar_done = true;
                ar_busy = false;
                state = ST_IDLE;
                break;

            case ST_ERROR:
                ar_error = true;
                ar_busy = false;
                state = ST_IDLE;
                break;
        }
    }
};

struct TestCase {
    int id;
    string category;
    string name;
    uint32_t prim_type; // 0=LINE, 1=TRI
    int x0, y0, x1, y1, x2, y2;
    uint32_t color;
    uint32_t fb_base;
    uint32_t fb_stride;
};

void build_testcases(vector<TestCase>& tests) {
    int id = 1;

    // Group 1: Horizontal Lines (15 tests)
    int h_lengths[] = {1, 2, 5, 10, 15, 25, 40, 75, 100, 150, 200, 300, 450, 500, 600};
    for (int l : h_lengths) {
        TestCase tc;
        tc.id = id++;
        tc.category = "Horizontal Lines";
        tc.name = "H-Line length=" + to_string(l);
        tc.prim_type = 0;
        tc.x0 = 10; tc.y0 = 20 + (id % 300);
        tc.x1 = tc.x0 + l; tc.y1 = tc.y0;
        tc.x2 = 0; tc.y2 = 0;
        tc.color = 0x00FF0000 | (id * 0x1234);
        tc.fb_base = 0x10000000;
        tc.fb_stride = 2560;
        tests.push_back(tc);
    }

    // Group 2: Vertical Lines (15 tests)
    int v_lengths[] = {1, 2, 5, 10, 15, 25, 40, 60, 80, 120, 160, 220, 300, 380, 450};
    for (int l : v_lengths) {
        TestCase tc;
        tc.id = id++;
        tc.category = "Vertical Lines";
        tc.name = "V-Line length=" + to_string(l);
        tc.prim_type = 0;
        tc.x0 = 20 + (id % 400); tc.y0 = 10;
        tc.x1 = tc.x0; tc.y1 = tc.y0 + l;
        tc.x2 = 0; tc.y2 = 0;
        tc.color = 0x0000FF00 | (id * 0x0521);
        tc.fb_base = 0x10000000;
        tc.fb_stride = 2560;
        tests.push_back(tc);
    }

    // Group 3: Diagonal Lines (45 degrees, slope=1, -1) (15 tests)
    int d_lengths[] = {1, 3, 7, 12, 18, 25, 35, 50, 70, 90, 120, 150, 200, 250, 300};
    for (int l : d_lengths) {
        TestCase tc;
        tc.id = id++;
        tc.category = "Diagonal Lines (45-deg)";
        tc.name = "Diag Line length=" + to_string(l);
        tc.prim_type = 0;
        bool flip_x = (id % 2 == 0);
        bool flip_y = (id % 4 >= 2);
        tc.x0 = flip_x ? (100 + l) : 100;
        tc.y0 = flip_y ? (100 + l) : 100;
        tc.x1 = flip_x ? 100 : (100 + l);
        tc.y1 = flip_y ? 100 : (100 + l);
        tc.x2 = 0; tc.y2 = 0;
        tc.color = 0x000000FF | (id * 0x0317);
        tc.fb_base = 0x10000000;
        tc.fb_stride = 2560;
        tests.push_back(tc);
    }

    // Group 4: Shallow Lines (|dx| > |dy|) (20 tests)
    for (int i = 0; i < 20; i++) {
        TestCase tc;
        tc.id = id++;
        tc.category = "Shallow Slopes (|dx| > |dy|)";
        int dx = 20 + (i * 15);
        int dy = 3 + (i * 2);
        tc.name = "Shallow Line dx=" + to_string(dx) + " dy=" + to_string(dy);
        tc.prim_type = 0;
        tc.x0 = 50; tc.y0 = 50 + (i * 10);
        tc.x1 = tc.x0 + ((i % 2 == 0) ? dx : -dx);
        tc.y1 = tc.y0 + ((i % 3 == 0) ? -dy : dy);
        tc.x2 = 0; tc.y2 = 0;
        tc.color = 0x00FFFF00 | (id * 0x0113);
        tc.fb_base = 0x10000000;
        tc.fb_stride = 2560;
        tests.push_back(tc);
    }

    // Group 5: Steep Lines (|dy| > |dx|) (20 tests)
    for (int i = 0; i < 20; i++) {
        TestCase tc;
        tc.id = id++;
        tc.category = "Steep Slopes (|dy| > |dx|)";
        int dx = 3 + (i * 2);
        int dy = 20 + (i * 12);
        tc.name = "Steep Line dx=" + to_string(dx) + " dy=" + to_string(dy);
        tc.prim_type = 0;
        tc.x0 = 100 + (i * 15); tc.y0 = 50;
        tc.x1 = tc.x0 + ((i % 2 == 0) ? dx : -dx);
        tc.y1 = tc.y0 + ((i % 3 == 0) ? -dy : dy);
        tc.x2 = 0; tc.y2 = 0;
        tc.color = 0x00FF00FF | (id * 0x0277);
        tc.fb_base = 0x10000000;
        tc.fb_stride = 2560;
        tests.push_back(tc);
    }

    // Group 6: Degenerate & Edge Boundaries (10 tests)
    int pts[][2] = {
        {0, 0}, {639, 0}, {0, 479}, {639, 479}, {320, 240},
        {10, 10}, {50, 50}, {100, 100}, {200, 200}, {500, 400}
    };
    for (int i = 0; i < 10; i++) {
        TestCase tc;
        tc.id = id++;
        tc.category = "Degenerate / Boundary Points";
        tc.name = "Single Point (" + to_string(pts[i][0]) + "," + to_string(pts[i][1]) + ")";
        tc.prim_type = 0;
        tc.x0 = pts[i][0]; tc.y0 = pts[i][1];
        tc.x1 = pts[i][0]; tc.y1 = pts[i][1];
        tc.x2 = 0; tc.y2 = 0;
        tc.color = 0x00FFFFFF;
        tc.fb_base = 0x10000000;
        tc.fb_stride = 2560;
        tests.push_back(tc);
    }

    // Group 7: Triangle Outlines (20 tests)
    for (int i = 0; i < 20; i++) {
        TestCase tc;
        tc.id = id++;
        tc.category = "Triangle Outlines";
        int s = 15 + (i * 12);
        tc.name = "Triangle size=" + to_string(s);
        tc.prim_type = 1;
        tc.x0 = 50 + (i * 10);      tc.y0 = 50 + (i * 8);
        tc.x1 = tc.x0 + s;          tc.y1 = tc.y0 + (s / 2);
        tc.x2 = tc.x0 + (s / 3);    tc.y2 = tc.y0 + s;
        tc.color = 0x00FFAA33 | (i * 0x0711);
        tc.fb_base = 0x10000000;
        tc.fb_stride = 2560;
        tests.push_back(tc);
    }

    // Group 8: Randomized Constrained Stress Tests (10 tests)
    uint32_t seed = 0x12345678;
    auto lfsr = [&]() {
        seed = (seed >> 1) ^ (-(seed & 1u) & 0xD0000001u);
        return seed;
    };
    for (int i = 0; i < 10; i++) {
        TestCase tc;
        tc.id = id++;
        tc.category = "Randomized Stress Lines/Triangles";
        tc.prim_type = (i % 2 == 0) ? 0 : 1;
        tc.x0 = lfsr() % 500; tc.y0 = lfsr() % 400;
        tc.x1 = lfsr() % 500; tc.y1 = lfsr() % 400;
        tc.x2 = lfsr() % 500; tc.y2 = lfsr() % 400;
        tc.name = (tc.prim_type == 0 ? "Random Line #" : "Random Tri #") + to_string(i + 1);
        tc.color = lfsr() & 0x00FFFFFF;
        tc.fb_base = 0x10000000;
        tc.fb_stride = 2560;
        tests.push_back(tc);
    }
}

int main() {
    cout << "================================================================================" << endl;
    cout << "      ARRAY RASTERIZER ACCELERATOR (AR) EXHAUSTIVE VERIFICATION SUITE           " << endl;
    cout << "                         (125 COMPREHENSIVE TESTCASES)                          " << endl;
    cout << "================================================================================" << endl;
    cout << endl;

    vector<TestCase> testcases;
    build_testcases(testcases);

    int passed = 0;
    int failed = 0;

    ofstream vcd("tb_ar_engine.vcd");
    vcd << "$date\n  " << __DATE__ << "\n$end\n$version\n  Synopsys VCS / Verdi Compatible VCD\n$end\n";
    vcd << "$timescale 1ns $end\n$scope module tb_ar_engine $end\n";
    vcd << "$var wire 1 ! clk $end\n";
    vcd << "$var wire 1 \" ar_start $end\n";
    vcd << "$var wire 1 # ar_busy $end\n";
    vcd << "$var wire 1 $ ar_done $end\n";
    vcd << "$var wire 1 % pixel_valid $end\n";
    vcd << "$var wire 32 & pixel_addr [31:0] $end\n";
    vcd << "$var wire 32 ' pixel_data [31:0] $end\n";
    vcd << "$upscope $end\n$enddefinitions $end\n";

    AREngineDUT dut;
    uint64_t sim_time = 0;

    string current_category = "";

    for (const auto& tc : testcases) {
        if (tc.category != current_category) {
            current_category = tc.category;
            cout << "\n>>> CATEGORY: " << current_category << " <<<\n" << endl;
        }

        vector<Pixel> exp;
        if (tc.prim_type == 0) {
            exp = golden_line(tc.x0, tc.y0, tc.x1, tc.y1, tc.color, tc.fb_base, tc.fb_stride);
        } else {
            auto s0 = golden_line(tc.x0, tc.y0, tc.x1, tc.y1, tc.color, tc.fb_base, tc.fb_stride);
            auto s1 = golden_line(tc.x1, tc.y1, tc.x2, tc.y2, tc.color, tc.fb_base, tc.fb_stride);
            auto s2 = golden_line(tc.x0, tc.y0, tc.x2, tc.y2, tc.color, tc.fb_base, tc.fb_stride);
            exp.insert(exp.end(), s0.begin(), s0.end());
            exp.insert(exp.end(), s1.begin(), s1.end());
            exp.insert(exp.end(), s2.begin(), s2.end());
        }

        vector<uint32_t> vmem;
        vmem.push_back(((uint32_t)(tc.y0 & 0xFFFF) << 16) | (uint32_t)(tc.x0 & 0xFFFF));
        vmem.push_back(((uint32_t)(tc.y1 & 0xFFFF) << 16) | (uint32_t)(tc.x1 & 0xFFFF));
        if (tc.prim_type == 1) {
            vmem.push_back(((uint32_t)(tc.y2 & 0xFFFF) << 16) | (uint32_t)(tc.x2 & 0xFFFF));
        }

        dut.reset();
        vector<Pixel> got;

        // Pulse start
        dut.clock_step(true, tc.prim_type, 0x1000, (uint32_t)vmem.size(), tc.color, tc.fb_base, tc.fb_stride,
                       false, false, 0, true);
        sim_time += 10;

        int timeout = 50000;
        int dma_beat = 0;
        bool dma_in_progress = false;
        int dma_wait = 0;

        while (!dut.ar_done && timeout-- > 0) {
            bool rm_done = false;
            bool rm_rvalid = false;
            uint32_t rm_rdata = 0;

            if (dma_in_progress) {
                if (dma_wait > 0) {
                    dma_wait--;
                } else if (dma_beat < (int)vmem.size()) {
                    rm_rvalid = true;
                    rm_rdata = vmem[dma_beat++];
                } else {
                    rm_done = true;
                    dma_in_progress = false;
                }
            }

            dut.clock_step(false, tc.prim_type, 0x1000, (uint32_t)vmem.size(), tc.color, tc.fb_base, tc.fb_stride,
                           rm_done, rm_rvalid, rm_rdata, true);

            if (dut.ar_rm_start) {
                dma_in_progress = true;
                dma_wait = 2;
                dma_beat = 0;
            }

            if (dut.ar_wm_pixel_valid) {
                got.push_back({dut.ar_wm_pixel_addr, dut.ar_wm_pixel_data});
            }

            if (tc.id <= 20) {
                vcd << "#" << sim_time << "\n";
                vcd << "1!\n";
                vcd << (dut.ar_busy ? "1#" : "0#") << "\n";
                vcd << (dut.ar_done ? "1$" : "0$") << "\n";
                vcd << (dut.ar_wm_pixel_valid ? "1%" : "0%") << "\n";
                if (dut.ar_wm_pixel_valid) {
                    vcd << "b" << bitset<32>(dut.ar_wm_pixel_addr) << " &\n";
                    vcd << "b" << bitset<32>(dut.ar_wm_pixel_data) << " '\n";
                }
            }

            sim_time += 10;
        }

        bool match = true;
        if (got.size() != exp.size()) {
            match = false;
        } else {
            for (size_t i = 0; i < got.size(); i++) {
                if (got[i].addr != exp[i].addr || got[i].data != exp[i].data) {
                    match = false;
                    break;
                }
            }
        }

        cout << "TEST " << right << setfill('0') << setw(3) << tc.id << ": " << setfill(' ') << left << setw(35) << tc.name;
        ostringstream in_oss;
        if (tc.prim_type == 0) {
            in_oss << "(" << tc.x0 << "," << tc.y0 << ")->(" << tc.x1 << "," << tc.y1 << ")";
        } else {
            in_oss << "(" << tc.x0 << "," << tc.y0 << ")->(" << tc.x1 << "," << tc.y1 << ")->(" << tc.x2 << "," << tc.y2 << ")";
        }
        cout << " | In: " << left << setw(36) << in_oss.str();
        cout << " | Pixels: Got " << right << setw(4) << got.size() << " / Exp " << setw(4) << exp.size();
        if (match) {
            cout << " | [PASS]" << endl;
            passed++;
        } else {
            cout << " | [FAIL]" << endl;
            failed++;
        }
    }

    cout << "\n================================================================================" << endl;
    cout << "                          VERIFICATION SUMMARY REPORT                           " << endl;
    cout << "================================================================================" << endl;
    cout << "  TOTAL TEST CASES RUN : " << testcases.size() << endl;
    cout << "  TOTAL PASSED         : " << passed << endl;
    cout << "  TOTAL FAILED         : " << failed << endl;
    cout << "  PASS RATE            : " << fixed << setprecision(2) << ((double)passed / testcases.size() * 100.0) << "%" << endl;
    if (failed == 0) {
        cout << "  OVERALL STATUS       : *** ALL " << testcases.size() << " TESTCASES PASSED PERFECTLY (100% SUCCESS) ***" << endl;
    } else {
        cout << "  OVERALL STATUS       : *** VERIFICATION FAILED (" << failed << " ERRORS) ***" << endl;
    }
    cout << "================================================================================" << endl;

    vcd.close();
    return (failed == 0) ? 0 : 1;
}
