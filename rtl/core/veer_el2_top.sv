// =============================================================================
// veer_el2_top.sv – VeeR EL2 RV32IMC CPU Core Top-Level Wrapper
//
// Replaces the placeholder veer_el2_stub.v with the actual VeeR EL2 RISC-V
// processor core (el2_veer_wrapper).
//
// Features:
//   • Instantiates el2_veer_wrapper from Cores-VeeR-EL2
//   • Internal SRAM interface instantiation (el2_mem_if)
//   • Multiplexes and arbitrates VeeR EL2 AXI4 master channels (LSU & IFU)
//     onto the top-level 32-bit AXI4 master interface (m_axi_* -> Interconnect S00)
//   • Performs 64-bit to 32-bit width conversion:
//       - 64-bit IFU / LSU burst reads decomposed into 2x 32-bit beats
//       - 32/16/8-bit LSU reads handled as single 32-bit beats
//       - LSU writes routed to low/high word based on address/strobe
//   • Maps external interrupts (ar_irq + ext_int[7:0]) to VeeR PIC (extintsrc_req)
//   • Configurable boot / reset vector (BOOT_ADDR parameter)
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "common_defines.vh"
`include "el2_def.sv"

module veer_el2_top 
import el2_pkg::*;
#(
`include "el2_param.vh"
,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8,
    parameter BOOT_ADDR  = 32'h3000_0000   // Boot ROM base address
)(
    input  wire                  clk,
    input  wire                  rst_l,      // active-low synchronous reset (VeeR convention)

    // ---- External interrupt inputs ----
    input  wire                  ar_irq,     // from AR Control (done/error)
    input  wire [7:0]            ext_int,    // external interrupts:
                                             //   [0] = UART RX interrupt
                                             //   [1] = GPIO interrupt
                                             //   [2] = SPI transfer done
                                             //   [3] = Timer A interrupt
                                             //   [4] = Timer B interrupt
                                             //   [5] = Watchdog pre-warning IRQ
                                             //   [7:6] = reserved

    // ---- AXI4 Master Interface (Interconnect S00) ----
    // Write address channel
    output reg  [ID_WIDTH-1:0]   m_axi_awid,
    output reg  [ADDR_WIDTH-1:0] m_axi_awaddr,
    output reg  [7:0]            m_axi_awlen,
    output reg  [2:0]            m_axi_awsize,
    output reg  [1:0]            m_axi_awburst,
    output wire                  m_axi_awlock,
    output reg  [3:0]            m_axi_awcache,
    output reg  [2:0]            m_axi_awprot,
    output wire [3:0]            m_axi_awqos,
    output reg                   m_axi_awvalid,
    input  wire                  m_axi_awready,

    // Write data channel
    output reg  [DATA_WIDTH-1:0] m_axi_wdata,
    output reg  [STRB_WIDTH-1:0] m_axi_wstrb,
    output reg                   m_axi_wlast,
    output reg                   m_axi_wvalid,
    input  wire                  m_axi_wready,

    // Write response channel
    input  wire [ID_WIDTH-1:0]   m_axi_bid,
    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output wire                  m_axi_bready,

    // Read address channel
    output reg  [ID_WIDTH-1:0]   m_axi_arid,
    output reg  [ADDR_WIDTH-1:0] m_axi_araddr,
    output reg  [7:0]            m_axi_arlen,
    output reg  [2:0]            m_axi_arsize,
    output reg  [1:0]            m_axi_arburst,
    output wire                  m_axi_arlock,
    output reg  [3:0]            m_axi_arcache,
    output reg  [2:0]            m_axi_arprot,
    output wire [3:0]            m_axi_arqos,
    output reg                   m_axi_arvalid,
    input  wire                  m_axi_arready,

    // Read data channel
    input  wire [ID_WIDTH-1:0]   m_axi_rid,
    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output reg                   m_axi_rready
);

    // =========================================================================
    // Core internal signals
    // =========================================================================
    // LSU AXI signals (64-bit data)
    logic                     lsu_axi_awvalid;
    logic                     lsu_axi_awready;
    logic [pt.LSU_BUS_TAG-1:0] lsu_axi_awid;
    logic [31:0]              lsu_axi_awaddr;
    logic [3:0]               lsu_axi_awregion;
    logic [7:0]               lsu_axi_awlen;
    logic [2:0]               lsu_axi_awsize;
    logic [1:0]               lsu_axi_awburst;
    logic                     lsu_axi_awlock;
    logic [3:0]               lsu_axi_awcache;
    logic [2:0]               lsu_axi_awprot;
    logic [3:0]               lsu_axi_awqos;

    logic                     lsu_axi_wvalid;
    logic                     lsu_axi_wready;
    logic [63:0]              lsu_axi_wdata;
    logic [7:0]               lsu_axi_wstrb;
    logic                     lsu_axi_wlast;

    logic                     lsu_axi_bvalid;
    logic                     lsu_axi_bready;
    logic [1:0]               lsu_axi_bresp;
    logic [pt.LSU_BUS_TAG-1:0] lsu_axi_bid;

    wire                      lsu_axi_arvalid;
    wire                      lsu_axi_arready;
    wire [pt.LSU_BUS_TAG-1:0] lsu_axi_arid;
    wire [31:0]               lsu_axi_araddr;
    wire [3:0]                lsu_axi_arregion;
    wire [7:0]                lsu_axi_arlen;
    wire [2:0]                lsu_axi_arsize;
    wire [1:0]                lsu_axi_arburst;
    wire                      lsu_axi_arlock;
    wire [3:0]                lsu_axi_arcache;
    wire [2:0]                lsu_axi_arprot;
    wire [3:0]                lsu_axi_arqos;

    reg                       lsu_axi_rvalid;
    wire                      lsu_axi_rready;
    reg  [pt.LSU_BUS_TAG-1:0] lsu_axi_rid;
    reg  [63:0]               lsu_axi_rdata;
    reg  [1:0]                lsu_axi_rresp;
    reg                       lsu_axi_rlast;

    // IFU AXI signals (64-bit data, read only)
    wire                      ifu_axi_arvalid;
    wire                      ifu_axi_arready;
    wire [pt.IFU_BUS_TAG-1:0] ifu_axi_arid;
    wire [31:0]               ifu_axi_araddr;
    wire [3:0]                ifu_axi_arregion;
    wire [7:0]                ifu_axi_arlen;
    wire [2:0]                ifu_axi_arsize;
    wire [1:0]                ifu_axi_arburst;
    wire                      ifu_axi_arlock;
    wire [3:0]                ifu_axi_arcache;
    wire [2:0]                ifu_axi_arprot;
    wire [3:0]                ifu_axi_arqos;

    reg                       ifu_axi_rvalid;
    wire                      ifu_axi_rready;
    reg  [pt.IFU_BUS_TAG-1:0] ifu_axi_rid;
    reg  [63:0]               ifu_axi_rdata;
    reg  [1:0]                ifu_axi_rresp;
    reg                       ifu_axi_rlast;

    // Memory export interface instance
    el2_mem_if mem_export ();

    // Interrupt aggregation for VeeR PIC (Programmable Interrupt Controller)
    wire [pt.PIC_TOTAL_INT:1] extintsrc_req;
    assign extintsrc_req = {
        {(pt.PIC_TOTAL_INT - 7){1'b0}},
        ext_int[5],   // bit 7: Watchdog pre-warning
        ext_int[4],   // bit 6: Timer B match
        ext_int[3],   // bit 5: Timer A match
        ext_int[2],   // bit 4: SPI done
        ext_int[1],   // bit 3: GPIO interrupt
        ext_int[0],   // bit 2: UART RX interrupt
        ar_irq        // bit 1: AR rasterizer done/error
    };

    // =========================================================================
    // Core Instantiation (el2_veer_wrapper)
    // =========================================================================
    el2_veer_wrapper rvtop (
        .clk                    (clk),
        .rst_l                  (rst_l),
        .dbg_rst_l              (rst_l),
        .rst_vec                (BOOT_ADDR[31:1]),
        .nmi_int                (1'b0),
        .nmi_vec                (31'd0),
        .jtag_id                (31'h0000_0001),

        // Trace outputs (unconnected)
        .trace_rv_i_insn_ip     (),
        .trace_rv_i_address_ip  (),
        .trace_rv_i_valid_ip    (),
        .trace_rv_i_exception_ip(),
        .trace_rv_i_ecause_ip   (),
        .trace_rv_i_interrupt_ip(),
        .trace_rv_i_tval_ip     (),

        // LSU AXI Interface
        .lsu_axi_awvalid        (lsu_axi_awvalid),
        .lsu_axi_awready        (lsu_axi_awready),
        .lsu_axi_awid           (lsu_axi_awid),
        .lsu_axi_awaddr         (lsu_axi_awaddr),
        .lsu_axi_awregion       (lsu_axi_awregion),
        .lsu_axi_awlen          (lsu_axi_awlen),
        .lsu_axi_awsize         (lsu_axi_awsize),
        .lsu_axi_awburst        (lsu_axi_awburst),
        .lsu_axi_awlock         (lsu_axi_awlock),
        .lsu_axi_awcache        (lsu_axi_awcache),
        .lsu_axi_awprot         (lsu_axi_awprot),
        .lsu_axi_awqos          (lsu_axi_awqos),

        .lsu_axi_wvalid         (lsu_axi_wvalid),
        .lsu_axi_wready         (lsu_axi_wready),
        .lsu_axi_wdata          (lsu_axi_wdata),
        .lsu_axi_wstrb          (lsu_axi_wstrb),
        .lsu_axi_wlast          (lsu_axi_wlast),

        .lsu_axi_bvalid         (lsu_axi_bvalid),
        .lsu_axi_bready         (lsu_axi_bready),
        .lsu_axi_bresp          (lsu_axi_bresp),
        .lsu_axi_bid            (lsu_axi_bid),

        .lsu_axi_arvalid        (lsu_axi_arvalid),
        .lsu_axi_arready        (lsu_axi_arready),
        .lsu_axi_arid           (lsu_axi_arid),
        .lsu_axi_araddr         (lsu_axi_araddr),
        .lsu_axi_arregion       (lsu_axi_arregion),
        .lsu_axi_arlen          (lsu_axi_arlen),
        .lsu_axi_arsize         (lsu_axi_arsize),
        .lsu_axi_arburst        (lsu_axi_arburst),
        .lsu_axi_arlock         (lsu_axi_arlock),
        .lsu_axi_arcache        (lsu_axi_arcache),
        .lsu_axi_arprot         (lsu_axi_arprot),
        .lsu_axi_arqos          (lsu_axi_arqos),

        .lsu_axi_rvalid         (lsu_axi_rvalid),
        .lsu_axi_rready         (lsu_axi_rready),
        .lsu_axi_rid            (lsu_axi_rid),
        .lsu_axi_rdata          (lsu_axi_rdata),
        .lsu_axi_rresp          (lsu_axi_rresp),
        .lsu_axi_rlast          (lsu_axi_rlast),

        // IFU AXI Interface
        .ifu_axi_awvalid        (),
        .ifu_axi_awready        (1'b0),
        .ifu_axi_awid           (),
        .ifu_axi_awaddr         (),
        .ifu_axi_awregion       (),
        .ifu_axi_awlen          (),
        .ifu_axi_awsize         (),
        .ifu_axi_awburst        (),
        .ifu_axi_awlock         (),
        .ifu_axi_awcache        (),
        .ifu_axi_awprot         (),
        .ifu_axi_awqos          (),

        .ifu_axi_wvalid         (),
        .ifu_axi_wready         (1'b0),
        .ifu_axi_wdata          (),
        .ifu_axi_wstrb          (),
        .ifu_axi_wlast          (),

        .ifu_axi_bvalid         (1'b0),
        .ifu_axi_bready         (),
        .ifu_axi_bresp          (2'b00),
        .ifu_axi_bid            ('0),

        .ifu_axi_arvalid        (ifu_axi_arvalid),
        .ifu_axi_arready        (ifu_axi_arready),
        .ifu_axi_arid           (ifu_axi_arid),
        .ifu_axi_araddr         (ifu_axi_araddr),
        .ifu_axi_arregion       (ifu_axi_arregion),
        .ifu_axi_arlen          (ifu_axi_arlen),
        .ifu_axi_arsize         (ifu_axi_arsize),
        .ifu_axi_arburst        (ifu_axi_arburst),
        .ifu_axi_arlock         (ifu_axi_arlock),
        .ifu_axi_arcache        (ifu_axi_arcache),
        .ifu_axi_arprot         (ifu_axi_arprot),
        .ifu_axi_arqos          (ifu_axi_arqos),

        .ifu_axi_rvalid         (ifu_axi_rvalid),
        .ifu_axi_rready         (ifu_axi_rready),
        .ifu_axi_rid            (ifu_axi_rid),
        .ifu_axi_rdata          (ifu_axi_rdata),
        .ifu_axi_rresp          (ifu_axi_rresp),
        .ifu_axi_rlast          (ifu_axi_rlast),

        // System Bus (SB) AXI (tied off)
        .sb_axi_awvalid         (),
        .sb_axi_awready         (1'b0),
        .sb_axi_awid            (),
        .sb_axi_awaddr          (),
        .sb_axi_awregion        (),
        .sb_axi_awlen           (),
        .sb_axi_awsize          (),
        .sb_axi_awburst         (),
        .sb_axi_awlock          (),
        .sb_axi_awcache         (),
        .sb_axi_awprot          (),
        .sb_axi_awqos           (),

        .sb_axi_wvalid          (),
        .sb_axi_wready          (1'b0),
        .sb_axi_wdata           (),
        .sb_axi_wstrb           (),
        .sb_axi_wlast           (),

        .sb_axi_bvalid          (1'b0),
        .sb_axi_bready          (),
        .sb_axi_bresp           (2'b00),
        .sb_axi_bid             ('0),

        .sb_axi_arvalid         (),
        .sb_axi_arready         (1'b0),
        .sb_axi_arid            (),
        .sb_axi_araddr          (),
        .sb_axi_arregion        (),
        .sb_axi_arlen           (),
        .sb_axi_arsize          (),
        .sb_axi_arburst         (),
        .sb_axi_arlock          (),
        .sb_axi_arcache         (),
        .sb_axi_arprot          (),
        .sb_axi_arqos           (),

        .sb_axi_rvalid          (1'b0),
        .sb_axi_rready          (),
        .sb_axi_rid             ('0),
        .sb_axi_rdata           (64'd0),
        .sb_axi_rresp           (2'b00),
        .sb_axi_rlast           (1'b0),

        // DMA AXI Slave (tied off)
        .dma_axi_awvalid        (1'b0),
        .dma_axi_awready        (),
        .dma_axi_awid           ('0),
        .dma_axi_awaddr         (32'd0),
        .dma_axi_awsize         (3'd0),
        .dma_axi_awprot         (3'd0),
        .dma_axi_awlen          (8'd0),
        .dma_axi_awburst        (2'd0),

        .dma_axi_wvalid         (1'b0),
        .dma_axi_wready         (),
        .dma_axi_wdata          (64'd0),
        .dma_axi_wstrb          (8'd0),
        .dma_axi_wlast          (1'b0),

        .dma_axi_bvalid         (),
        .dma_axi_bready         (1'b1),
        .dma_axi_bresp          (),
        .dma_axi_bid            (),

        .dma_axi_arvalid        (1'b0),
        .dma_axi_arready        (),
        .dma_axi_arid           ('0),
        .dma_axi_araddr         (32'd0),
        .dma_axi_arsize         (3'd0),
        .dma_axi_arprot         (3'd0),
        .dma_axi_arlen          (8'd0),
        .dma_axi_arburst        (2'd0),

        .dma_axi_rvalid         (),
        .dma_axi_rready         (1'b1),
        .dma_axi_rid            (),
        .dma_axi_rdata          (),
        .dma_axi_rresp          (),
        .dma_axi_rlast          (),

        // Clock enables
        .lsu_bus_clk_en         (1'b1),
        .ifu_bus_clk_en         (1'b1),
        .dbg_bus_clk_en         (1'b1),
        .dma_bus_clk_en         (1'b1),

        // ECC error flags
        .iccm_ecc_single_error  (),
        .iccm_ecc_double_error  (),
        .dccm_ecc_single_error  (),
        .dccm_ecc_double_error  (),
        .dccm_write_readback_error(),

        // Memory and cache export interfaces
        .el2_mem_export         (mem_export.veer_sram_src),
        .el2_icache_export      (mem_export.veer_icache_src),

        // Interrupts
        .timer_int              (ext_int[3]),
        .soft_int               (1'b0),
        .extintsrc_req          (extintsrc_req),

        // Performance counters
        .dec_tlu_perfcnt0       (),
        .dec_tlu_perfcnt1       (),
        .dec_tlu_perfcnt2       (),
        .dec_tlu_perfcnt3       (),

        // JTAG interface (tied off)
        .jtag_tck               (1'b0),
        .jtag_tms               (1'b0),
        .jtag_tdi               (1'b0),
        .jtag_trst_n            (1'b1),
        .jtag_tdo               (),
        .jtag_tdoEn             (),
        .core_id                (28'd0),

        // MPC / CPU run controls
        .mpc_debug_halt_req     (1'b0),
        .mpc_debug_run_req      (1'b0),
        .mpc_reset_run_req      (1'b1),   // run immediately upon reset release
        .mpc_debug_halt_ack     (),
        .mpc_debug_run_ack      (),
        .debug_brkpt_status     (),

        .i_cpu_halt_req         (1'b0),
        .o_cpu_halt_ack         (),
        .o_cpu_halt_status      (),
        .o_debug_mode_status    (),
        .i_cpu_run_req          (1'b0),
        .o_cpu_run_ack          (),
        .scan_mode              (1'b0),
        .mbist_mode             (1'b0),

        .dmi_core_enable        (1'b1),
        .dmi_uncore_enable      (1'b0),
        .dmi_uncore_en          (),
        .dmi_uncore_wr_en       (),
        .dmi_uncore_addr        (),
        .dmi_uncore_wdata       (),
        .dmi_uncore_rdata       (32'd0),
        .dmi_active             ()
    );

    // =========================================================================
    // AXI4 Write Channel Adapter (LSU -> m_axi)
    // =========================================================================
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awqos   = 4'h0;

    // Detect if store byte strobes target the high 32-bit word [63:32]
    wire lsu_wr_high = (lsu_axi_wstrb[7:4] != 4'b0000);

    always_comb begin
        m_axi_awvalid   = lsu_axi_awvalid;
        m_axi_awid      = {{(ID_WIDTH-pt.LSU_BUS_TAG){1'b0}}, lsu_axi_awid};
        m_axi_awaddr    = lsu_axi_awaddr;
        m_axi_awlen     = 8'd0;
        m_axi_awsize    = (lsu_axi_awsize > 3'b010) ? 3'b010 : lsu_axi_awsize;
        m_axi_awburst   = lsu_axi_awburst;
        m_axi_awcache   = lsu_axi_awcache;
        m_axi_awprot    = lsu_axi_awprot;
        lsu_axi_awready = m_axi_awready;

        m_axi_wvalid    = lsu_axi_wvalid;
        m_axi_wlast     = 1'b1;
        m_axi_wdata     = lsu_wr_high ? lsu_axi_wdata[63:32] : lsu_axi_wdata[31:0];
        m_axi_wstrb     = lsu_wr_high ? lsu_axi_wstrb[7:4]   : lsu_axi_wstrb[3:0];
        lsu_axi_wready  = m_axi_wready;

        lsu_axi_bvalid  = m_axi_bvalid;
        lsu_axi_bresp   = m_axi_bresp;
        lsu_axi_bid     = m_axi_bid[pt.LSU_BUS_TAG-1:0];
    end
    assign m_axi_bready = lsu_axi_bready;

    // =========================================================================
    // AXI4 Read Channel Arbiter & Width Converter (LSU & IFU -> m_axi)
    // =========================================================================
    assign m_axi_arlock = 1'b0;
    assign m_axi_arqos  = 4'h0;

    localparam [2:0]
        R_IDLE         = 3'd0,
        R_LSU_SINGLE   = 3'd1,
        R_LSU_BURST0   = 3'd2,
        R_LSU_BURST1   = 3'd3,
        R_IFU_BURST0   = 3'd4,
        R_IFU_BURST1   = 3'd5;

    reg [2:0]  r_state;
    reg [31:0] r_beat0_buf;
    reg [ID_WIDTH-1:0] r_saved_id;

    assign ifu_axi_arready = (r_state == R_IDLE) && !lsu_axi_arvalid && m_axi_arready;
    assign lsu_axi_arready = (r_state == R_IDLE) && m_axi_arready;

    always @(posedge clk or negedge rst_l) begin
        if (!rst_l) begin
            r_state         <= R_IDLE;
            r_beat0_buf     <= 32'd0;
            r_saved_id      <= {ID_WIDTH{1'b0}};

            m_axi_arvalid   <= 1'b0;
            m_axi_arid      <= {ID_WIDTH{1'b0}};
            m_axi_araddr    <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen     <= 8'd0;
            m_axi_arsize    <= 3'b010;
            m_axi_arburst   <= 2'b01;
            m_axi_arcache   <= 4'd0;
            m_axi_arprot    <= 3'd0;
            m_axi_rready    <= 1'b0;

            lsu_axi_rvalid  <= 1'b0;
            lsu_axi_rdata   <= 64'd0;
            lsu_axi_rresp   <= 2'b00;
            lsu_axi_rlast   <= 1'b0;
            lsu_axi_rid     <= '0;

            ifu_axi_rvalid  <= 1'b0;
            ifu_axi_rdata   <= 64'd0;
            ifu_axi_rresp   <= 2'b00;
            ifu_axi_rlast   <= 1'b0;
            ifu_axi_rid     <= '0;

        end else begin
            // Default single-cycle flags
            lsu_axi_rvalid <= 1'b0;
            ifu_axi_rvalid <= 1'b0;

            case (r_state)
                // -------------------------------------------------------------
                // IDLE: Schedule LSU or IFU read
                // -------------------------------------------------------------
                R_IDLE: begin
                    m_axi_rready <= 1'b0;

                    if (lsu_axi_arvalid) begin
                        // LSU read has priority
                        if (lsu_axi_arsize == 3'b011) begin
                            // 64-bit read requested -> 2-beat 32-bit burst
                            m_axi_arid    <= {1'b0, {(ID_WIDTH-1-pt.LSU_BUS_TAG){1'b0}}, lsu_axi_arid};
                            m_axi_araddr  <= {lsu_axi_araddr[31:3], 3'b000};
                            m_axi_arlen   <= 8'd1;  // 2 beats
                            m_axi_arsize  <= 3'b010; // 4 bytes
                            m_axi_arburst <= 2'b01;  // INCR
                            m_axi_arcache <= lsu_axi_arcache;
                            m_axi_arprot  <= lsu_axi_arprot;
                            m_axi_arvalid <= 1'b1;

                            if (m_axi_arready) begin
                                m_axi_arvalid <= 1'b0;
                                r_state       <= R_LSU_BURST0;
                            end
                        end else begin
                            // 32-bit, 16-bit, or 8-bit single beat read
                            m_axi_arid    <= {1'b0, {(ID_WIDTH-1-pt.LSU_BUS_TAG){1'b0}}, lsu_axi_arid};
                            m_axi_araddr  <= lsu_axi_araddr;
                            m_axi_arlen   <= 8'd0;  // 1 beat
                            m_axi_arsize  <= lsu_axi_arsize;
                            m_axi_arburst <= lsu_axi_arburst;
                            m_axi_arcache <= lsu_axi_arcache;
                            m_axi_arprot  <= lsu_axi_arprot;
                            m_axi_arvalid <= 1'b1;

                            if (m_axi_arready) begin
                                m_axi_arvalid <= 1'b0;
                                r_state       <= R_LSU_SINGLE;
                            end
                        end

                    end else if (ifu_axi_arvalid) begin
                        // IFU 64-bit instruction cacheline fetch -> 2-beat 32-bit burst
                        m_axi_arid    <= {1'b1, {(ID_WIDTH-1-pt.IFU_BUS_TAG){1'b0}}, ifu_axi_arid};
                        m_axi_araddr  <= {ifu_axi_araddr[31:3], 3'b000};
                        m_axi_arlen   <= 8'd1;  // 2 beats
                        m_axi_arsize  <= 3'b010; // 4 bytes
                        m_axi_arburst <= 2'b01;  // INCR
                        m_axi_arcache <= ifu_axi_arcache;
                        m_axi_arprot  <= ifu_axi_arprot;
                        m_axi_arvalid <= 1'b1;

                        if (m_axi_arready) begin
                            m_axi_arvalid <= 1'b0;
                            r_state       <= R_IFU_BURST0;
                        end
                    end else begin
                        m_axi_arvalid <= 1'b0;
                    end
                end

                // -------------------------------------------------------------
                // LSU Single Beat Read
                // -------------------------------------------------------------
                R_LSU_SINGLE: begin
                    m_axi_rready <= lsu_axi_rready;
                    if (m_axi_rvalid) begin
                        lsu_axi_rdata  <= {m_axi_rdata, m_axi_rdata}; // duplicate word to both lanes
                        lsu_axi_rresp  <= m_axi_rresp;
                        lsu_axi_rlast  <= 1'b1;
                        lsu_axi_rid    <= m_axi_rid[pt.LSU_BUS_TAG-1:0];
                        lsu_axi_rvalid <= 1'b1;

                        if (lsu_axi_rready) begin
                            m_axi_rready <= 1'b0;
                            r_state      <= R_IDLE;
                        end
                    end
                end

                // -------------------------------------------------------------
                // LSU 64-bit Burst (Beat 0: Lower 32-bit word)
                // -------------------------------------------------------------
                R_LSU_BURST0: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid) begin
                        r_beat0_buf <= m_axi_rdata;
                        r_saved_id  <= m_axi_rid;
                        r_state     <= R_LSU_BURST1;
                    end
                end

                // -------------------------------------------------------------
                // LSU 64-bit Burst (Beat 1: Upper 32-bit word)
                // -------------------------------------------------------------
                R_LSU_BURST1: begin
                    m_axi_rready <= lsu_axi_rready;
                    if (m_axi_rvalid) begin
                        lsu_axi_rdata  <= {m_axi_rdata, r_beat0_buf}; // {upper, lower}
                        lsu_axi_rresp  <= m_axi_rresp;
                        lsu_axi_rlast  <= 1'b1;
                        lsu_axi_rid    <= m_axi_rid[pt.LSU_BUS_TAG-1:0];
                        lsu_axi_rvalid <= 1'b1;

                        if (lsu_axi_rready) begin
                            m_axi_rready <= 1'b0;
                            r_state      <= R_IDLE;
                        end
                    end
                end

                // -------------------------------------------------------------
                // IFU 64-bit Burst (Beat 0: Lower 32-bit word)
                // -------------------------------------------------------------
                R_IFU_BURST0: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid) begin
                        r_beat0_buf <= m_axi_rdata;
                        r_saved_id  <= m_axi_rid;
                        r_state     <= R_IFU_BURST1;
                    end
                end

                // -------------------------------------------------------------
                // IFU 64-bit Burst (Beat 1: Upper 32-bit word)
                // -------------------------------------------------------------
                R_IFU_BURST1: begin
                    m_axi_rready <= ifu_axi_rready;
                    if (m_axi_rvalid) begin
                        ifu_axi_rdata  <= {m_axi_rdata, r_beat0_buf}; // {upper, lower}
                        ifu_axi_rresp  <= m_axi_rresp;
                        ifu_axi_rlast  <= 1'b1;
                        ifu_axi_rid    <= m_axi_rid[pt.IFU_BUS_TAG-1:0];
                        ifu_axi_rvalid <= 1'b1;

                        if (ifu_axi_rready) begin
                            m_axi_rready <= 1'b0;
                            r_state      <= R_IDLE;
                        end
                    end
                end

                default: r_state <= R_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
