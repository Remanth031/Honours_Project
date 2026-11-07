// =============================================================================
// ar_soc_top.v  –  Array Rasterizer SoC Top-Level
//
// Instantiates:
//   • axi_interconnect_wrap_4x11 (4 masters × 11 slaves)
//   • Masters (interconnect slave ports S00–S03)
//       S00  veer_el2_top     – VeeR EL2 RV32IMC CPU Core
//       S01  ar_read_master   – AR engine vertex/primitive read path
//       S02  ar_write_master  – AR engine pixel write path
//       S03  vga_controller   – VGA framebuffer read + display driver
//   • Slaves (interconnect master ports M00–M10)
//       M00  data_mem         – Data Memory        0x0000_0000 (16 MB)
//       M01  framebuffer      – Framebuffer         0x1000_0000 (16 MB)
//       M02  ar_control       – AR Control/Status   0x2000_0000 ( 4 KB)
//       M03  hpm              – Perf Monitor        0x2001_0000 ( 4 KB)
//       M04  vga_ctrl_regs    – VGA Config Regs     0x2002_0000 ( 4 KB)
//       M05  axi_uart_top     – AXI-Lite UART       0x2003_0000 ( 4 KB)
//       M06  gpio             – GPIO Controller     0x2004_0000 ( 4 KB)
//       M07  spi              – SPI Master          0x2005_0000 ( 4 KB)
//       M08  timer            – Dual Timer          0x2006_0000 ( 4 KB)
//       M09  reset_ctrl       – Reset & WDT Ctrl    0x2007_0000 ( 4 KB)
//       M10  boot_rom         – Boot ROM            0x3000_0000 ( 4 KB)
//   • Accelerator Core:
//       ar_engine             – Hardware line & triangle rasterizer
//
// Address Map:
//   0x0000_0000 – 0x00FF_FFFF   Data Memory        (M00, 24-bit = 16 MB)
//   0x1000_0000 – 0x10FF_FFFF   Framebuffer        (M01, 24-bit = 16 MB)
//   0x2000_0000 – 0x2000_0FFF   AR Control Regs    (M02, 12-bit =  4 KB)
//   0x2001_0000 – 0x2001_0FFF   HPM Regs           (M03, 12-bit =  4 KB)
//   0x2002_0000 – 0x2002_0FFF   VGA Config Regs    (M04, 12-bit =  4 KB)
//   0x2003_0000 – 0x2003_0FFF   UART Regs          (M05, 12-bit =  4 KB)
//   0x2004_0000 – 0x2004_0FFF   GPIO Regs          (M06, 12-bit =  4 KB)
//   0x2005_0000 – 0x2005_0FFF   SPI Regs           (M07, 12-bit =  4 KB)
//   0x2006_0000 – 0x2006_0FFF   Timer Regs         (M08, 12-bit =  4 KB)
//   0x2007_0000 – 0x2007_0FFF   Reset/WDT Regs     (M09, 12-bit =  4 KB)
//   0x3000_0000 – 0x3000_0FFF   Boot ROM           (M10, 12-bit =  4 KB)
//
// Connectivity matrix (1 = connected):
//           M00 M01 M02 M03 M04 M05 M06 M07 M08 M09 M10
//  S00(CPU)  1   1   1   1   1   1   1   1   1   1   1   (full access)
//  S01(ARR)  1   0   0   0   0   0   0   0   0   0   0   (read data mem)
//  S02(ARW)  0   1   0   0   0   0   0   0   0   0   0   (write framebuffer)
//  S03(VGA)  0   1   0   0   0   0   0   0   0   0   0   (read framebuffer)
// =============================================================================
// Language: Verilog 2001
`resetall
`timescale 1ns / 1ps
`default_nettype none

module ar_soc_top #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8
)(
    input  wire        clk,
    input  wire        rst,            // active-high synchronous reset
    input  wire        por_reset,      // power-on reset input
    output wire        sys_reset_req,  // system reset request output (WDT/soft)

    // ---- VGA Display Outputs ----
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        vga_blank_n,
    output wire        vga_sync_n,
    output wire        vga_clk_out,

    // ---- UART Serial Interface ----
    output wire        uart_tx,    // UART transmit (to external terminal/host)
    input  wire        uart_rx,    // UART receive  (from external terminal/host)

    // ---- GPIO Interface ----
    output wire [31:0] gpio_out,   // general-purpose outputs
    input  wire [31:0] gpio_in,    // general-purpose inputs

    // ---- SPI Master Interface ----
    output wire        spi_sclk,   // SPI serial clock
    output wire        spi_mosi,   // SPI master-out slave-in
    input  wire        spi_miso,   // SPI master-in slave-out
    output wire        spi_cs_n,   // SPI chip select (active low)

    // ---- External Interrupts from SoC ----
    output wire        ar_irq      // AR done/error interrupt
);

// =============================================================================
// Local parameters – Address Map
// =============================================================================
localparam M00_BASE  = 32'h0000_0000;  // Data Memory
localparam M00_BITS  = 24;
localparam M01_BASE  = 32'h1000_0000;  // Framebuffer
localparam M01_BITS  = 24;
localparam M02_BASE  = 32'h2000_0000;  // AR Control
localparam M02_BITS  = 12;
localparam M03_BASE  = 32'h2001_0000;  // HPM
localparam M03_BITS  = 12;
localparam M04_BASE  = 32'h2002_0000;  // VGA Config Regs
localparam M04_BITS  = 12;
localparam M05_BASE  = 32'h2003_0000;  // AXI-Lite UART
localparam M05_BITS  = 12;
localparam M06_BASE  = 32'h2004_0000;  // GPIO
localparam M06_BITS  = 12;
localparam M07_BASE  = 32'h2005_0000;  // SPI
localparam M07_BITS  = 12;
localparam M08_BASE  = 32'h2006_0000;  // Timer
localparam M08_BITS  = 12;
localparam M09_BASE  = 32'h2007_0000;  // Reset Controller / WDT
localparam M09_BITS  = 12;
localparam M10_BASE  = 32'h3000_0000;  // Boot ROM
localparam M10_BITS  = 12;

// =============================================================================
// Reset resolution
// =============================================================================
wire por_rst_in        = por_reset | rst;
wire sys_reset_active  = rst | sys_reset_req;

// =============================================================================
// AXI bus signal declarations
// Format: <port>_<channel>_<signal>
//   port = s00..s03 (master→interconnect) or m00..m10 (interconnect→slave)
// =============================================================================

// S00 – VeeR EL2 CPU
wire [ID_WIDTH-1:0]   s00_axi_awid,    s00_axi_arid,    s00_axi_bid,    s00_axi_rid;
wire [ADDR_WIDTH-1:0] s00_axi_awaddr,  s00_axi_araddr;
wire [7:0]            s00_axi_awlen,   s00_axi_arlen;
wire [2:0]            s00_axi_awsize,  s00_axi_arsize;
wire [1:0]            s00_axi_awburst, s00_axi_arburst;
wire                  s00_axi_awlock,  s00_axi_arlock;
wire [3:0]            s00_axi_awcache, s00_axi_arcache;
wire [2:0]            s00_axi_awprot,  s00_axi_arprot;
wire [3:0]            s00_axi_awqos,   s00_axi_arqos;
wire                  s00_axi_awvalid, s00_axi_awready;
wire [DATA_WIDTH-1:0] s00_axi_wdata,   s00_axi_rdata;
wire [STRB_WIDTH-1:0] s00_axi_wstrb;
wire                  s00_axi_wlast,   s00_axi_rlast;
wire                  s00_axi_wvalid,  s00_axi_wready;
wire [1:0]            s00_axi_bresp,   s00_axi_rresp;
wire                  s00_axi_bvalid,  s00_axi_bready;
wire                  s00_axi_arvalid, s00_axi_arready;
wire                  s00_axi_rvalid,  s00_axi_rready;

// S01 – AR Read Master
wire [ID_WIDTH-1:0]   s01_axi_awid,    s01_axi_arid,    s01_axi_bid,    s01_axi_rid;
wire [ADDR_WIDTH-1:0] s01_axi_awaddr,  s01_axi_araddr;
wire [7:0]            s01_axi_awlen,   s01_axi_arlen;
wire [2:0]            s01_axi_awsize,  s01_axi_arsize;
wire [1:0]            s01_axi_awburst, s01_axi_arburst;
wire                  s01_axi_awlock,  s01_axi_arlock;
wire [3:0]            s01_axi_awcache, s01_axi_arcache;
wire [2:0]            s01_axi_awprot,  s01_axi_arprot;
wire [3:0]            s01_axi_awqos,   s01_axi_arqos;
wire                  s01_axi_awvalid, s01_axi_awready;
wire [DATA_WIDTH-1:0] s01_axi_wdata,   s01_axi_rdata;
wire [STRB_WIDTH-1:0] s01_axi_wstrb;
wire                  s01_axi_wlast,   s01_axi_rlast;
wire                  s01_axi_wvalid,  s01_axi_wready;
wire [1:0]            s01_axi_bresp,   s01_axi_rresp;
wire                  s01_axi_bvalid,  s01_axi_bready;
wire                  s01_axi_arvalid, s01_axi_arready;
wire                  s01_axi_rvalid,  s01_axi_rready;

// S02 – AR Write Master
wire [ID_WIDTH-1:0]   s02_axi_awid,    s02_axi_arid,    s02_axi_bid,    s02_axi_rid;
wire [ADDR_WIDTH-1:0] s02_axi_awaddr,  s02_axi_araddr;
wire [7:0]            s02_axi_awlen,   s02_axi_arlen;
wire [2:0]            s02_axi_awsize,  s02_axi_arsize;
wire [1:0]            s02_axi_awburst, s02_axi_arburst;
wire                  s02_axi_awlock,  s02_axi_arlock;
wire [3:0]            s02_axi_awcache, s02_axi_arcache;
wire [2:0]            s02_axi_awprot,  s02_axi_arprot;
wire [3:0]            s02_axi_awqos,   s02_axi_arqos;
wire                  s02_axi_awvalid, s02_axi_awready;
wire [DATA_WIDTH-1:0] s02_axi_wdata,   s02_axi_rdata;
wire [STRB_WIDTH-1:0] s02_axi_wstrb;
wire                  s02_axi_wlast,   s02_axi_rlast;
wire                  s02_axi_wvalid,  s02_axi_wready;
wire [1:0]            s02_axi_bresp,   s02_axi_rresp;
wire                  s02_axi_bvalid,  s02_axi_bready;
wire                  s02_axi_arvalid, s02_axi_arready;
wire                  s02_axi_rvalid,  s02_axi_rready;

// S03 – VGA Controller
wire [ID_WIDTH-1:0]   s03_axi_awid,    s03_axi_arid,    s03_axi_bid,    s03_axi_rid;
wire [ADDR_WIDTH-1:0] s03_axi_awaddr,  s03_axi_araddr;
wire [7:0]            s03_axi_awlen,   s03_axi_arlen;
wire [2:0]            s03_axi_awsize,  s03_axi_arsize;
wire [1:0]            s03_axi_awburst, s03_axi_arburst;
wire                  s03_axi_awlock,  s03_axi_arlock;
wire [3:0]            s03_axi_awcache, s03_axi_arcache;
wire [2:0]            s03_axi_awprot,  s03_axi_arprot;
wire [3:0]            s03_axi_awqos,   s03_axi_arqos;
wire                  s03_axi_awvalid, s03_axi_awready;
wire [DATA_WIDTH-1:0] s03_axi_wdata,   s03_axi_rdata;
wire [STRB_WIDTH-1:0] s03_axi_wstrb;
wire                  s03_axi_wlast,   s03_axi_rlast;
wire                  s03_axi_wvalid,  s03_axi_wready;
wire [1:0]            s03_axi_bresp,   s03_axi_rresp;
wire                  s03_axi_bvalid,  s03_axi_bready;
wire                  s03_axi_arvalid, s03_axi_arready;
wire                  s03_axi_rvalid,  s03_axi_rready;

// ---- M00 ----
wire [ID_WIDTH-1:0]   m00_axi_awid,    m00_axi_arid,    m00_axi_bid,    m00_axi_rid;
wire [ADDR_WIDTH-1:0] m00_axi_awaddr,  m00_axi_araddr;
wire [7:0]            m00_axi_awlen,   m00_axi_arlen;
wire [2:0]            m00_axi_awsize,  m00_axi_arsize;
wire [1:0]            m00_axi_awburst, m00_axi_arburst;
wire                  m00_axi_awlock,  m00_axi_arlock;
wire [3:0]            m00_axi_awcache, m00_axi_arcache;
wire [2:0]            m00_axi_awprot,  m00_axi_arprot;
wire [3:0]            m00_axi_awqos,   m00_axi_arqos;
wire [3:0]            m00_axi_awregion,m00_axi_arregion;
wire                  m00_axi_awvalid, m00_axi_awready;
wire [DATA_WIDTH-1:0] m00_axi_wdata,   m00_axi_rdata;
wire [STRB_WIDTH-1:0] m00_axi_wstrb;
wire                  m00_axi_wlast,   m00_axi_rlast;
wire                  m00_axi_wvalid,  m00_axi_wready;
wire [1:0]            m00_axi_bresp,   m00_axi_rresp;
wire                  m00_axi_bvalid,  m00_axi_bready;
wire                  m00_axi_arvalid, m00_axi_arready;
wire                  m00_axi_rvalid,  m00_axi_rready;
// ---- M01 ----
wire [ID_WIDTH-1:0]   m01_axi_awid,    m01_axi_arid,    m01_axi_bid,    m01_axi_rid;
wire [ADDR_WIDTH-1:0] m01_axi_awaddr,  m01_axi_araddr;
wire [7:0]            m01_axi_awlen,   m01_axi_arlen;
wire [2:0]            m01_axi_awsize,  m01_axi_arsize;
wire [1:0]            m01_axi_awburst, m01_axi_arburst;
wire                  m01_axi_awlock,  m01_axi_arlock;
wire [3:0]            m01_axi_awcache, m01_axi_arcache;
wire [2:0]            m01_axi_awprot,  m01_axi_arprot;
wire [3:0]            m01_axi_awqos,   m01_axi_arqos;
wire [3:0]            m01_axi_awregion,m01_axi_arregion;
wire                  m01_axi_awvalid, m01_axi_awready;
wire [DATA_WIDTH-1:0] m01_axi_wdata,   m01_axi_rdata;
wire [STRB_WIDTH-1:0] m01_axi_wstrb;
wire                  m01_axi_wlast,   m01_axi_rlast;
wire                  m01_axi_wvalid,  m01_axi_wready;
wire [1:0]            m01_axi_bresp,   m01_axi_rresp;
wire                  m01_axi_bvalid,  m01_axi_bready;
wire                  m01_axi_arvalid, m01_axi_arready;
wire                  m01_axi_rvalid,  m01_axi_rready;
// ---- M02 ----
wire [ID_WIDTH-1:0]   m02_axi_awid,    m02_axi_arid,    m02_axi_bid,    m02_axi_rid;
wire [ADDR_WIDTH-1:0] m02_axi_awaddr,  m02_axi_araddr;
wire [7:0]            m02_axi_awlen,   m02_axi_arlen;
wire [2:0]            m02_axi_awsize,  m02_axi_arsize;
wire [1:0]            m02_axi_awburst, m02_axi_arburst;
wire                  m02_axi_awlock,  m02_axi_arlock;
wire [3:0]            m02_axi_awcache, m02_axi_arcache;
wire [2:0]            m02_axi_awprot,  m02_axi_arprot;
wire [3:0]            m02_axi_awqos,   m02_axi_arqos;
wire [3:0]            m02_axi_awregion,m02_axi_arregion;
wire                  m02_axi_awvalid, m02_axi_awready;
wire [DATA_WIDTH-1:0] m02_axi_wdata,   m02_axi_rdata;
wire [STRB_WIDTH-1:0] m02_axi_wstrb;
wire                  m02_axi_wlast,   m02_axi_rlast;
wire                  m02_axi_wvalid,  m02_axi_wready;
wire [1:0]            m02_axi_bresp,   m02_axi_rresp;
wire                  m02_axi_bvalid,  m02_axi_bready;
wire                  m02_axi_arvalid, m02_axi_arready;
wire                  m02_axi_rvalid,  m02_axi_rready;
// ---- M03 ----
wire [ID_WIDTH-1:0]   m03_axi_awid,    m03_axi_arid,    m03_axi_bid,    m03_axi_rid;
wire [ADDR_WIDTH-1:0] m03_axi_awaddr,  m03_axi_araddr;
wire [7:0]            m03_axi_awlen,   m03_axi_arlen;
wire [2:0]            m03_axi_awsize,  m03_axi_arsize;
wire [1:0]            m03_axi_awburst, m03_axi_arburst;
wire                  m03_axi_awlock,  m03_axi_arlock;
wire [3:0]            m03_axi_awcache, m03_axi_arcache;
wire [2:0]            m03_axi_awprot,  m03_axi_arprot;
wire [3:0]            m03_axi_awqos,   m03_axi_arqos;
wire [3:0]            m03_axi_awregion,m03_axi_arregion;
wire                  m03_axi_awvalid, m03_axi_awready;
wire [DATA_WIDTH-1:0] m03_axi_wdata,   m03_axi_rdata;
wire [STRB_WIDTH-1:0] m03_axi_wstrb;
wire                  m03_axi_wlast,   m03_axi_rlast;
wire                  m03_axi_wvalid,  m03_axi_wready;
wire [1:0]            m03_axi_bresp,   m03_axi_rresp;
wire                  m03_axi_bvalid,  m03_axi_bready;
wire                  m03_axi_arvalid, m03_axi_arready;
wire                  m03_axi_rvalid,  m03_axi_rready;
// ---- M04 ----
wire [ID_WIDTH-1:0]   m04_axi_awid,    m04_axi_arid,    m04_axi_bid,    m04_axi_rid;
wire [ADDR_WIDTH-1:0] m04_axi_awaddr,  m04_axi_araddr;
wire [7:0]            m04_axi_awlen,   m04_axi_arlen;
wire [2:0]            m04_axi_awsize,  m04_axi_arsize;
wire [1:0]            m04_axi_awburst, m04_axi_arburst;
wire                  m04_axi_awlock,  m04_axi_arlock;
wire [3:0]            m04_axi_awcache, m04_axi_arcache;
wire [2:0]            m04_axi_awprot,  m04_axi_arprot;
wire [3:0]            m04_axi_awqos,   m04_axi_arqos;
wire [3:0]            m04_axi_awregion,m04_axi_arregion;
wire                  m04_axi_awvalid, m04_axi_awready;
wire [DATA_WIDTH-1:0] m04_axi_wdata,   m04_axi_rdata;
wire [STRB_WIDTH-1:0] m04_axi_wstrb;
wire                  m04_axi_wlast,   m04_axi_rlast;
wire                  m04_axi_wvalid,  m04_axi_wready;
wire [1:0]            m04_axi_bresp,   m04_axi_rresp;
wire                  m04_axi_bvalid,  m04_axi_bready;
wire                  m04_axi_arvalid, m04_axi_arready;
wire                  m04_axi_rvalid,  m04_axi_rready;
// ---- M05 ----
wire [ID_WIDTH-1:0]   m05_axi_awid,    m05_axi_arid,    m05_axi_bid,    m05_axi_rid;
wire [ADDR_WIDTH-1:0] m05_axi_awaddr,  m05_axi_araddr;
wire [7:0]            m05_axi_awlen,   m05_axi_arlen;
wire [2:0]            m05_axi_awsize,  m05_axi_arsize;
wire [1:0]            m05_axi_awburst, m05_axi_arburst;
wire                  m05_axi_awlock,  m05_axi_arlock;
wire [3:0]            m05_axi_awcache, m05_axi_arcache;
wire [2:0]            m05_axi_awprot,  m05_axi_arprot;
wire [3:0]            m05_axi_awqos,   m05_axi_arqos;
wire [3:0]            m05_axi_awregion,m05_axi_arregion;
wire                  m05_axi_awvalid, m05_axi_awready;
wire [DATA_WIDTH-1:0] m05_axi_wdata,   m05_axi_rdata;
wire [STRB_WIDTH-1:0] m05_axi_wstrb;
wire                  m05_axi_wlast,   m05_axi_rlast;
wire                  m05_axi_wvalid,  m05_axi_wready;
wire [1:0]            m05_axi_bresp,   m05_axi_rresp;
wire                  m05_axi_bvalid,  m05_axi_bready;
wire                  m05_axi_arvalid, m05_axi_arready;
wire                  m05_axi_rvalid,  m05_axi_rready;
// ---- M06 ----
wire [ID_WIDTH-1:0]   m06_axi_awid,    m06_axi_arid,    m06_axi_bid,    m06_axi_rid;
wire [ADDR_WIDTH-1:0] m06_axi_awaddr,  m06_axi_araddr;
wire [7:0]            m06_axi_awlen,   m06_axi_arlen;
wire [2:0]            m06_axi_awsize,  m06_axi_arsize;
wire [1:0]            m06_axi_awburst, m06_axi_arburst;
wire                  m06_axi_awlock,  m06_axi_arlock;
wire [3:0]            m06_axi_awcache, m06_axi_arcache;
wire [2:0]            m06_axi_awprot,  m06_axi_arprot;
wire [3:0]            m06_axi_awqos,   m06_axi_arqos;
wire [3:0]            m06_axi_awregion,m06_axi_arregion;
wire                  m06_axi_awvalid, m06_axi_awready;
wire [DATA_WIDTH-1:0] m06_axi_wdata,   m06_axi_rdata;
wire [STRB_WIDTH-1:0] m06_axi_wstrb;
wire                  m06_axi_wlast,   m06_axi_rlast;
wire                  m06_axi_wvalid,  m06_axi_wready;
wire [1:0]            m06_axi_bresp,   m06_axi_rresp;
wire                  m06_axi_bvalid,  m06_axi_bready;
wire                  m06_axi_arvalid, m06_axi_arready;
wire                  m06_axi_rvalid,  m06_axi_rready;
// ---- M07 ----
wire [ID_WIDTH-1:0]   m07_axi_awid,    m07_axi_arid,    m07_axi_bid,    m07_axi_rid;
wire [ADDR_WIDTH-1:0] m07_axi_awaddr,  m07_axi_araddr;
wire [7:0]            m07_axi_awlen,   m07_axi_arlen;
wire [2:0]            m07_axi_awsize,  m07_axi_arsize;
wire [1:0]            m07_axi_awburst, m07_axi_arburst;
wire                  m07_axi_awlock,  m07_axi_arlock;
wire [3:0]            m07_axi_awcache, m07_axi_arcache;
wire [2:0]            m07_axi_awprot,  m07_axi_arprot;
wire [3:0]            m07_axi_awqos,   m07_axi_arqos;
wire [3:0]            m07_axi_awregion,m07_axi_arregion;
wire                  m07_axi_awvalid, m07_axi_awready;
wire [DATA_WIDTH-1:0] m07_axi_wdata,   m07_axi_rdata;
wire [STRB_WIDTH-1:0] m07_axi_wstrb;
wire                  m07_axi_wlast,   m07_axi_rlast;
wire                  m07_axi_wvalid,  m07_axi_wready;
wire [1:0]            m07_axi_bresp,   m07_axi_rresp;
wire                  m07_axi_bvalid,  m07_axi_bready;
wire                  m07_axi_arvalid, m07_axi_arready;
wire                  m07_axi_rvalid,  m07_axi_rready;
// ---- M08 ----
wire [ID_WIDTH-1:0]   m08_axi_awid,    m08_axi_arid,    m08_axi_bid,    m08_axi_rid;
wire [ADDR_WIDTH-1:0] m08_axi_awaddr,  m08_axi_araddr;
wire [7:0]            m08_axi_awlen,   m08_axi_arlen;
wire [2:0]            m08_axi_awsize,  m08_axi_arsize;
wire [1:0]            m08_axi_awburst, m08_axi_arburst;
wire                  m08_axi_awlock,  m08_axi_arlock;
wire [3:0]            m08_axi_awcache, m08_axi_arcache;
wire [2:0]            m08_axi_awprot,  m08_axi_arprot;
wire [3:0]            m08_axi_awqos,   m08_axi_arqos;
wire [3:0]            m08_axi_awregion,m08_axi_arregion;
wire                  m08_axi_awvalid, m08_axi_awready;
wire [DATA_WIDTH-1:0] m08_axi_wdata,   m08_axi_rdata;
wire [STRB_WIDTH-1:0] m08_axi_wstrb;
wire                  m08_axi_wlast,   m08_axi_rlast;
wire                  m08_axi_wvalid,  m08_axi_wready;
wire [1:0]            m08_axi_bresp,   m08_axi_rresp;
wire                  m08_axi_bvalid,  m08_axi_bready;
wire                  m08_axi_arvalid, m08_axi_arready;
wire                  m08_axi_rvalid,  m08_axi_rready;
// ---- M09 ----
wire [ID_WIDTH-1:0]   m09_axi_awid,    m09_axi_arid,    m09_axi_bid,    m09_axi_rid;
wire [ADDR_WIDTH-1:0] m09_axi_awaddr,  m09_axi_araddr;
wire [7:0]            m09_axi_awlen,   m09_axi_arlen;
wire [2:0]            m09_axi_awsize,  m09_axi_arsize;
wire [1:0]            m09_axi_awburst, m09_axi_arburst;
wire                  m09_axi_awlock,  m09_axi_arlock;
wire [3:0]            m09_axi_awcache, m09_axi_arcache;
wire [2:0]            m09_axi_awprot,  m09_axi_arprot;
wire [3:0]            m09_axi_awqos,   m09_axi_arqos;
wire [3:0]            m09_axi_awregion,m09_axi_arregion;
wire                  m09_axi_awvalid, m09_axi_awready;
wire [DATA_WIDTH-1:0] m09_axi_wdata,   m09_axi_rdata;
wire [STRB_WIDTH-1:0] m09_axi_wstrb;
wire                  m09_axi_wlast,   m09_axi_rlast;
wire                  m09_axi_wvalid,  m09_axi_wready;
wire [1:0]            m09_axi_bresp,   m09_axi_rresp;
wire                  m09_axi_bvalid,  m09_axi_bready;
wire                  m09_axi_arvalid, m09_axi_arready;
wire                  m09_axi_rvalid,  m09_axi_rready;
// ---- M10 ----
wire [ID_WIDTH-1:0]   m10_axi_awid,    m10_axi_arid,    m10_axi_bid,    m10_axi_rid;
wire [ADDR_WIDTH-1:0] m10_axi_awaddr,  m10_axi_araddr;
wire [7:0]            m10_axi_awlen,   m10_axi_arlen;
wire [2:0]            m10_axi_awsize,  m10_axi_arsize;
wire [1:0]            m10_axi_awburst, m10_axi_arburst;
wire                  m10_axi_awlock,  m10_axi_arlock;
wire [3:0]            m10_axi_awcache, m10_axi_arcache;
wire [2:0]            m10_axi_awprot,  m10_axi_arprot;
wire [3:0]            m10_axi_awqos,   m10_axi_arqos;
wire [3:0]            m10_axi_awregion,m10_axi_arregion;
wire                  m10_axi_awvalid, m10_axi_awready;
wire [DATA_WIDTH-1:0] m10_axi_wdata,   m10_axi_rdata;
wire [STRB_WIDTH-1:0] m10_axi_wstrb;
wire                  m10_axi_wlast,   m10_axi_rlast;
wire                  m10_axi_wvalid,  m10_axi_wready;
wire [1:0]            m10_axi_bresp,   m10_axi_rresp;
wire                  m10_axi_bvalid,  m10_axi_bready;
wire                  m10_axi_arvalid, m10_axi_arready;
wire                  m10_axi_rvalid,  m10_axi_rready;

// UART IP uses 12-bit IDs internally; adapt to SoC ID_WIDTH (8-bit)
wire [11:0]           m05_uart_bid_full, m05_uart_rid_full;
assign m05_axi_bid = m05_uart_bid_full[ID_WIDTH-1:0];
assign m05_axi_rid = m05_uart_rid_full[ID_WIDTH-1:0];

// =============================================================================
// Sideband / control signals
// =============================================================================

// AR Control ↔ AR engine
wire        ar_start, ar_reset;
wire  [1:0] ar_prim_type;
wire [31:0] ar_prim_base, ar_prim_count;
wire [23:0] ar_color;
wire [31:0] ar_fb_base_ctrl, ar_fb_stride_ctrl;
wire        ar_busy, ar_done, ar_error;

// AR Read Master sideband
wire        ar_rm_start, ar_rm_busy, ar_rm_done;
wire [31:0] ar_rm_base_addr;
wire [15:0] ar_rm_beat_count;
wire [31:0] ar_rm_rdata;
wire        ar_rm_rvalid;

// AR Write Master sideband
wire [31:0] ar_wm_pixel_data;
wire [31:0] ar_wm_pixel_addr;
wire        ar_wm_pixel_valid, ar_wm_pixel_ready;
wire        ar_wm_busy, ar_wm_done;

// VGA ctrl regs ↔ VGA controller
wire        vga_en;
wire [31:0] vga_fb_base, vga_fb_stride;
wire        vsync_active, hsync_active;
wire        vsync_pol, hsync_pol;
wire [15:0] h_total, h_active;
wire [15:0] v_total, v_active;
wire [15:0] h_sync_start, h_sync_end;
wire [15:0] v_sync_start, v_sync_end;

// Peripheral interrupts
wire uart_irq;
wire gpio_irq;
wire spi_irq;
wire timer_irq_a, timer_irq_b;
wire wdt_irq;

// VeeR EL2 CPU external interrupt vector [7:0]:
//   [0] = UART RX interrupt
//   [1] = GPIO interrupt
//   [2] = SPI transfer complete
//   [3] = Timer Channel A
//   [4] = Timer Channel B
//   [5] = Watchdog pre-warning IRQ
//   [7:6] = reserved
wire [7:0] cpu_ext_int = {
    2'b00,
    wdt_irq,
    timer_irq_b,
    timer_irq_a,
    spi_irq,
    gpio_irq,
    uart_irq
};

// HPM sideband event monitoring
wire ev_mem_read     = s00_axi_arvalid & s00_axi_arready;
wire ev_mem_write    = s00_axi_awvalid & s00_axi_awready;
wire ev_pixel_out    = ar_wm_pixel_valid & ar_wm_pixel_ready;
wire ev_ar_active    = ar_busy;
wire ev_setup        = 1'b0;
wire ev_irq_handling = 1'b0;

// =============================================================================
// AR Engine Instantiation
// =============================================================================
ar_engine #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH)
) u_ar_engine (
    .clk                (clk),
    .rst                (sys_reset_active),
    .ar_start           (ar_start),
    .ar_reset           (ar_reset),
    .ar_prim_type       (ar_prim_type),
    .ar_prim_base       (ar_prim_base),
    .ar_prim_count      (ar_prim_count),
    .ar_color           (ar_color),
    .ar_fb_base         (ar_fb_base_ctrl),
    .ar_fb_stride       (ar_fb_stride_ctrl),
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
    .ar_wm_pixel_ready  (ar_wm_pixel_ready),
    .ar_wm_busy         (ar_wm_busy),
    .ar_wm_done         (ar_wm_done)
);

// =============================================================================
// AXI Interconnect 4×11
// =============================================================================
axi_interconnect_wrap_4x11 #(
    .DATA_WIDTH          (DATA_WIDTH),
    .ADDR_WIDTH          (ADDR_WIDTH),
    .STRB_WIDTH          (STRB_WIDTH),
    .ID_WIDTH            (ID_WIDTH),
    .AWUSER_ENABLE       (0),
    .AWUSER_WIDTH        (1),
    .WUSER_ENABLE        (0),
    .WUSER_WIDTH         (1),
    .BUSER_ENABLE        (0),
    .BUSER_WIDTH         (1),
    .ARUSER_ENABLE       (0),
    .ARUSER_WIDTH        (1),
    .RUSER_ENABLE        (0),
    .RUSER_WIDTH         (1),
    .FORWARD_ID          (0),
    .M_REGIONS           (1),

    // --- M00: Data Memory ---
    .M00_BASE_ADDR       (M00_BASE),
    .M00_ADDR_WIDTH      ({1{32'd24}}),
    .M00_CONNECT_READ    (4'b0011),   // CPU + AR Read
    .M00_CONNECT_WRITE   (4'b0001),   // CPU write only
    .M00_SECURE          (1'b0),

    // --- M01: Framebuffer ---
    .M01_BASE_ADDR       (M01_BASE),
    .M01_ADDR_WIDTH      ({1{32'd24}}),
    .M01_CONNECT_READ    (4'b1001),   // VGA + CPU read
    .M01_CONNECT_WRITE   (4'b0101),   // AR Write + CPU write
    .M01_SECURE          (1'b0),

    // --- M02: AR Control ---
    .M02_BASE_ADDR       (M02_BASE),
    .M02_ADDR_WIDTH      ({1{32'd12}}),
    .M02_CONNECT_READ    (4'b0001),
    .M02_CONNECT_WRITE   (4'b0001),
    .M02_SECURE          (1'b0),

    // --- M03: HPM ---
    .M03_BASE_ADDR       (M03_BASE),
    .M03_ADDR_WIDTH      ({1{32'd12}}),
    .M03_CONNECT_READ    (4'b0001),
    .M03_CONNECT_WRITE   (4'b0001),
    .M03_SECURE          (1'b0),

    // --- M04: VGA Config Regs ---
    .M04_BASE_ADDR       (M04_BASE),
    .M04_ADDR_WIDTH      ({1{32'd12}}),
    .M04_CONNECT_READ    (4'b0001),
    .M04_CONNECT_WRITE   (4'b0001),
    .M04_SECURE          (1'b0),

    // --- M05: AXI-Lite UART ---
    .M05_BASE_ADDR       (M05_BASE),
    .M05_ADDR_WIDTH      ({1{32'd12}}),
    .M05_CONNECT_READ    (4'b0001),
    .M05_CONNECT_WRITE   (4'b0001),
    .M05_SECURE          (1'b0),

    // --- M06: GPIO ---
    .M06_BASE_ADDR       (M06_BASE),
    .M06_ADDR_WIDTH      ({1{32'd12}}),
    .M06_CONNECT_READ    (4'b0001),
    .M06_CONNECT_WRITE   (4'b0001),
    .M06_SECURE          (1'b0),

    // --- M07: SPI ---
    .M07_BASE_ADDR       (M07_BASE),
    .M07_ADDR_WIDTH      ({1{32'd12}}),
    .M07_CONNECT_READ    (4'b0001),
    .M07_CONNECT_WRITE   (4'b0001),
    .M07_SECURE          (1'b0),

    // --- M08: Timer ---
    .M08_BASE_ADDR       (M08_BASE),
    .M08_ADDR_WIDTH      ({1{32'd12}}),
    .M08_CONNECT_READ    (4'b0001),
    .M08_CONNECT_WRITE   (4'b0001),
    .M08_SECURE          (1'b0),

    // --- M09: Reset Controller ---
    .M09_BASE_ADDR       (M09_BASE),
    .M09_ADDR_WIDTH      ({1{32'd12}}),
    .M09_CONNECT_READ    (4'b0001),
    .M09_CONNECT_WRITE   (4'b0001),
    .M09_SECURE          (1'b0),

    // --- M10: Boot ROM ---
    .M10_BASE_ADDR       (M10_BASE),
    .M10_ADDR_WIDTH      ({1{32'd12}}),
    .M10_CONNECT_READ    (4'b0001),
    .M10_CONNECT_WRITE   (4'b0001),
    .M10_SECURE          (1'b0)
) u_interconnect (
    .clk                (clk),
    .rst                (sys_reset_active),

    // ---- S00: VeeR EL2 CPU ----
    .s00_axi_awid       (s00_axi_awid),
    .s00_axi_awaddr     (s00_axi_awaddr),
    .s00_axi_awlen      (s00_axi_awlen),
    .s00_axi_awsize     (s00_axi_awsize),
    .s00_axi_awburst    (s00_axi_awburst),
    .s00_axi_awlock     (s00_axi_awlock),
    .s00_axi_awcache    (s00_axi_awcache),
    .s00_axi_awprot     (s00_axi_awprot),
    .s00_axi_awqos      (s00_axi_awqos),
    .s00_axi_awuser     (1'b0),
    .s00_axi_awvalid    (s00_axi_awvalid),
    .s00_axi_awready    (s00_axi_awready),
    .s00_axi_wdata      (s00_axi_wdata),
    .s00_axi_wstrb      (s00_axi_wstrb),
    .s00_axi_wlast      (s00_axi_wlast),
    .s00_axi_wuser      (1'b0),
    .s00_axi_wvalid     (s00_axi_wvalid),
    .s00_axi_wready     (s00_axi_wready),
    .s00_axi_bid        (s00_axi_bid),
    .s00_axi_bresp      (s00_axi_bresp),
    .s00_axi_buser      (),
    .s00_axi_bvalid     (s00_axi_bvalid),
    .s00_axi_bready     (s00_axi_bready),
    .s00_axi_arid       (s00_axi_arid),
    .s00_axi_araddr     (s00_axi_araddr),
    .s00_axi_arlen      (s00_axi_arlen),
    .s00_axi_arsize     (s00_axi_arsize),
    .s00_axi_arburst    (s00_axi_arburst),
    .s00_axi_arlock     (s00_axi_arlock),
    .s00_axi_arcache    (s00_axi_arcache),
    .s00_axi_arprot     (s00_axi_arprot),
    .s00_axi_arqos      (s00_axi_arqos),
    .s00_axi_aruser     (1'b0),
    .s00_axi_arvalid    (s00_axi_arvalid),
    .s00_axi_arready    (s00_axi_arready),
    .s00_axi_rid        (s00_axi_rid),
    .s00_axi_rdata      (s00_axi_rdata),
    .s00_axi_rresp      (s00_axi_rresp),
    .s00_axi_rlast      (s00_axi_rlast),
    .s00_axi_ruser      (),
    .s00_axi_rvalid     (s00_axi_rvalid),
    .s00_axi_rready     (s00_axi_rready),

    // ---- S01: AR Read Master ----
    .s01_axi_awid       (s01_axi_awid),
    .s01_axi_awaddr     (s01_axi_awaddr),
    .s01_axi_awlen      (s01_axi_awlen),
    .s01_axi_awsize     (s01_axi_awsize),
    .s01_axi_awburst    (s01_axi_awburst),
    .s01_axi_awlock     (s01_axi_awlock),
    .s01_axi_awcache    (s01_axi_awcache),
    .s01_axi_awprot     (s01_axi_awprot),
    .s01_axi_awqos      (s01_axi_awqos),
    .s01_axi_awuser     (1'b0),
    .s01_axi_awvalid    (s01_axi_awvalid),
    .s01_axi_awready    (s01_axi_awready),
    .s01_axi_wdata      (s01_axi_wdata),
    .s01_axi_wstrb      (s01_axi_wstrb),
    .s01_axi_wlast      (s01_axi_wlast),
    .s01_axi_wuser      (1'b0),
    .s01_axi_wvalid     (s01_axi_wvalid),
    .s01_axi_wready     (s01_axi_wready),
    .s01_axi_bid        (s01_axi_bid),
    .s01_axi_bresp      (s01_axi_bresp),
    .s01_axi_buser      (),
    .s01_axi_bvalid     (s01_axi_bvalid),
    .s01_axi_bready     (s01_axi_bready),
    .s01_axi_arid       (s01_axi_arid),
    .s01_axi_araddr     (s01_axi_araddr),
    .s01_axi_arlen      (s01_axi_arlen),
    .s01_axi_arsize     (s01_axi_arsize),
    .s01_axi_arburst    (s01_axi_arburst),
    .s01_axi_arlock     (s01_axi_arlock),
    .s01_axi_arcache    (s01_axi_arcache),
    .s01_axi_arprot     (s01_axi_arprot),
    .s01_axi_arqos      (s01_axi_arqos),
    .s01_axi_aruser     (1'b0),
    .s01_axi_arvalid    (s01_axi_arvalid),
    .s01_axi_arready    (s01_axi_arready),
    .s01_axi_rid        (s01_axi_rid),
    .s01_axi_rdata      (s01_axi_rdata),
    .s01_axi_rresp      (s01_axi_rresp),
    .s01_axi_rlast      (s01_axi_rlast),
    .s01_axi_ruser      (),
    .s01_axi_rvalid     (s01_axi_rvalid),
    .s01_axi_rready     (s01_axi_rready),

    // ---- S02: AR Write Master ----
    .s02_axi_awid       (s02_axi_awid),
    .s02_axi_awaddr     (s02_axi_awaddr),
    .s02_axi_awlen      (s02_axi_awlen),
    .s02_axi_awsize     (s02_axi_awsize),
    .s02_axi_awburst    (s02_axi_awburst),
    .s02_axi_awlock     (s02_axi_awlock),
    .s02_axi_awcache    (s02_axi_awcache),
    .s02_axi_awprot     (s02_axi_awprot),
    .s02_axi_awqos      (s02_axi_awqos),
    .s02_axi_awuser     (1'b0),
    .s02_axi_awvalid    (s02_axi_awvalid),
    .s02_axi_awready    (s02_axi_awready),
    .s02_axi_wdata      (s02_axi_wdata),
    .s02_axi_wstrb      (s02_axi_wstrb),
    .s02_axi_wlast      (s02_axi_wlast),
    .s02_axi_wuser      (1'b0),
    .s02_axi_wvalid     (s02_axi_wvalid),
    .s02_axi_wready     (s02_axi_wready),
    .s02_axi_bid        (s02_axi_bid),
    .s02_axi_bresp      (s02_axi_bresp),
    .s02_axi_buser      (),
    .s02_axi_bvalid     (s02_axi_bvalid),
    .s02_axi_bready     (s02_axi_bready),
    .s02_axi_arid       (s02_axi_arid),
    .s02_axi_araddr     (s02_axi_araddr),
    .s02_axi_arlen      (s02_axi_arlen),
    .s02_axi_arsize     (s02_axi_arsize),
    .s02_axi_arburst    (s02_axi_arburst),
    .s02_axi_arlock     (s02_axi_arlock),
    .s02_axi_arcache    (s02_axi_arcache),
    .s02_axi_arprot     (s02_axi_arprot),
    .s02_axi_arqos      (s02_axi_arqos),
    .s02_axi_aruser     (1'b0),
    .s02_axi_arvalid    (s02_axi_arvalid),
    .s02_axi_arready    (s02_axi_arready),
    .s02_axi_rid        (s02_axi_rid),
    .s02_axi_rdata      (s02_axi_rdata),
    .s02_axi_rresp      (s02_axi_rresp),
    .s02_axi_rlast      (s02_axi_rlast),
    .s02_axi_ruser      (),
    .s02_axi_rvalid     (s02_axi_rvalid),
    .s02_axi_rready     (s02_axi_rready),

    // ---- S03: VGA Controller ----
    .s03_axi_awid       (s03_axi_awid),
    .s03_axi_awaddr     (s03_axi_awaddr),
    .s03_axi_awlen      (s03_axi_awlen),
    .s03_axi_awsize     (s03_axi_awsize),
    .s03_axi_awburst    (s03_axi_awburst),
    .s03_axi_awlock     (s03_axi_awlock),
    .s03_axi_awcache    (s03_axi_awcache),
    .s03_axi_awprot     (s03_axi_awprot),
    .s03_axi_awqos      (s03_axi_awqos),
    .s03_axi_awuser     (1'b0),
    .s03_axi_awvalid    (s03_axi_awvalid),
    .s03_axi_awready    (s03_axi_awready),
    .s03_axi_wdata      (s03_axi_wdata),
    .s03_axi_wstrb      (s03_axi_wstrb),
    .s03_axi_wlast      (s03_axi_wlast),
    .s03_axi_wuser      (1'b0),
    .s03_axi_wvalid     (s03_axi_wvalid),
    .s03_axi_wready     (s03_axi_wready),
    .s03_axi_bid        (s03_axi_bid),
    .s03_axi_bresp      (s03_axi_bresp),
    .s03_axi_buser      (),
    .s03_axi_bvalid     (s03_axi_bvalid),
    .s03_axi_bready     (s03_axi_bready),
    .s03_axi_arid       (s03_axi_arid),
    .s03_axi_araddr     (s03_axi_araddr),
    .s03_axi_arlen      (s03_axi_arlen),
    .s03_axi_arsize     (s03_axi_arsize),
    .s03_axi_arburst    (s03_axi_arburst),
    .s03_axi_arlock     (s03_axi_arlock),
    .s03_axi_arcache    (s03_axi_arcache),
    .s03_axi_arprot     (s03_axi_arprot),
    .s03_axi_arqos      (s03_axi_arqos),
    .s03_axi_aruser     (1'b0),
    .s03_axi_arvalid    (s03_axi_arvalid),
    .s03_axi_arready    (s03_axi_arready),
    .s03_axi_rid        (s03_axi_rid),
    .s03_axi_rdata      (s03_axi_rdata),
    .s03_axi_rresp      (s03_axi_rresp),
    .s03_axi_rlast      (s03_axi_rlast),
    .s03_axi_ruser      (),
    .s03_axi_rvalid     (s03_axi_rvalid),
    .s03_axi_rready     (s03_axi_rready),
    // ---- M00 ----
    .m00_axi_awid       (m00_axi_awid),
    .m00_axi_awaddr     (m00_axi_awaddr),
    .m00_axi_awlen      (m00_axi_awlen),
    .m00_axi_awsize     (m00_axi_awsize),
    .m00_axi_awburst    (m00_axi_awburst),
    .m00_axi_awlock     (m00_axi_awlock),
    .m00_axi_awcache    (m00_axi_awcache),
    .m00_axi_awprot     (m00_axi_awprot),
    .m00_axi_awqos      (m00_axi_awqos),
    .m00_axi_awregion   (m00_axi_awregion),
    .m00_axi_awuser     (),
    .m00_axi_awvalid    (m00_axi_awvalid),
    .m00_axi_awready    (m00_axi_awready),
    .m00_axi_wdata      (m00_axi_wdata),
    .m00_axi_wstrb      (m00_axi_wstrb),
    .m00_axi_wlast      (m00_axi_wlast),
    .m00_axi_wuser      (),
    .m00_axi_wvalid     (m00_axi_wvalid),
    .m00_axi_wready     (m00_axi_wready),
    .m00_axi_bid        (m00_axi_bid),
    .m00_axi_bresp      (m00_axi_bresp),
    .m00_axi_buser      (1'b0),
    .m00_axi_bvalid     (m00_axi_bvalid),
    .m00_axi_bready     (m00_axi_bready),
    .m00_axi_arid       (m00_axi_arid),
    .m00_axi_araddr     (m00_axi_araddr),
    .m00_axi_arlen      (m00_axi_arlen),
    .m00_axi_arsize     (m00_axi_arsize),
    .m00_axi_arburst    (m00_axi_arburst),
    .m00_axi_arlock     (m00_axi_arlock),
    .m00_axi_arcache    (m00_axi_arcache),
    .m00_axi_arprot     (m00_axi_arprot),
    .m00_axi_arqos      (m00_axi_arqos),
    .m00_axi_arregion   (m00_axi_arregion),
    .m00_axi_aruser     (),
    .m00_axi_arvalid    (m00_axi_arvalid),
    .m00_axi_arready    (m00_axi_arready),
    .m00_axi_rid        (m00_axi_rid),
    .m00_axi_rdata      (m00_axi_rdata),
    .m00_axi_rresp      (m00_axi_rresp),
    .m00_axi_rlast      (m00_axi_rlast),
    .m00_axi_ruser      (1'b0),
    .m00_axi_rvalid     (m00_axi_rvalid),
    .m00_axi_rready     (m00_axi_rready),

    // ---- M01 ----
    .m01_axi_awid       (m01_axi_awid),
    .m01_axi_awaddr     (m01_axi_awaddr),
    .m01_axi_awlen      (m01_axi_awlen),
    .m01_axi_awsize     (m01_axi_awsize),
    .m01_axi_awburst    (m01_axi_awburst),
    .m01_axi_awlock     (m01_axi_awlock),
    .m01_axi_awcache    (m01_axi_awcache),
    .m01_axi_awprot     (m01_axi_awprot),
    .m01_axi_awqos      (m01_axi_awqos),
    .m01_axi_awregion   (m01_axi_awregion),
    .m01_axi_awuser     (),
    .m01_axi_awvalid    (m01_axi_awvalid),
    .m01_axi_awready    (m01_axi_awready),
    .m01_axi_wdata      (m01_axi_wdata),
    .m01_axi_wstrb      (m01_axi_wstrb),
    .m01_axi_wlast      (m01_axi_wlast),
    .m01_axi_wuser      (),
    .m01_axi_wvalid     (m01_axi_wvalid),
    .m01_axi_wready     (m01_axi_wready),
    .m01_axi_bid        (m01_axi_bid),
    .m01_axi_bresp      (m01_axi_bresp),
    .m01_axi_buser      (1'b0),
    .m01_axi_bvalid     (m01_axi_bvalid),
    .m01_axi_bready     (m01_axi_bready),
    .m01_axi_arid       (m01_axi_arid),
    .m01_axi_araddr     (m01_axi_araddr),
    .m01_axi_arlen      (m01_axi_arlen),
    .m01_axi_arsize     (m01_axi_arsize),
    .m01_axi_arburst    (m01_axi_arburst),
    .m01_axi_arlock     (m01_axi_arlock),
    .m01_axi_arcache    (m01_axi_arcache),
    .m01_axi_arprot     (m01_axi_arprot),
    .m01_axi_arqos      (m01_axi_arqos),
    .m01_axi_arregion   (m01_axi_arregion),
    .m01_axi_aruser     (),
    .m01_axi_arvalid    (m01_axi_arvalid),
    .m01_axi_arready    (m01_axi_arready),
    .m01_axi_rid        (m01_axi_rid),
    .m01_axi_rdata      (m01_axi_rdata),
    .m01_axi_rresp      (m01_axi_rresp),
    .m01_axi_rlast      (m01_axi_rlast),
    .m01_axi_ruser      (1'b0),
    .m01_axi_rvalid     (m01_axi_rvalid),
    .m01_axi_rready     (m01_axi_rready),

    // ---- M02 ----
    .m02_axi_awid       (m02_axi_awid),
    .m02_axi_awaddr     (m02_axi_awaddr),
    .m02_axi_awlen      (m02_axi_awlen),
    .m02_axi_awsize     (m02_axi_awsize),
    .m02_axi_awburst    (m02_axi_awburst),
    .m02_axi_awlock     (m02_axi_awlock),
    .m02_axi_awcache    (m02_axi_awcache),
    .m02_axi_awprot     (m02_axi_awprot),
    .m02_axi_awqos      (m02_axi_awqos),
    .m02_axi_awregion   (m02_axi_awregion),
    .m02_axi_awuser     (),
    .m02_axi_awvalid    (m02_axi_awvalid),
    .m02_axi_awready    (m02_axi_awready),
    .m02_axi_wdata      (m02_axi_wdata),
    .m02_axi_wstrb      (m02_axi_wstrb),
    .m02_axi_wlast      (m02_axi_wlast),
    .m02_axi_wuser      (),
    .m02_axi_wvalid     (m02_axi_wvalid),
    .m02_axi_wready     (m02_axi_wready),
    .m02_axi_bid        (m02_axi_bid),
    .m02_axi_bresp      (m02_axi_bresp),
    .m02_axi_buser      (1'b0),
    .m02_axi_bvalid     (m02_axi_bvalid),
    .m02_axi_bready     (m02_axi_bready),
    .m02_axi_arid       (m02_axi_arid),
    .m02_axi_araddr     (m02_axi_araddr),
    .m02_axi_arlen      (m02_axi_arlen),
    .m02_axi_arsize     (m02_axi_arsize),
    .m02_axi_arburst    (m02_axi_arburst),
    .m02_axi_arlock     (m02_axi_arlock),
    .m02_axi_arcache    (m02_axi_arcache),
    .m02_axi_arprot     (m02_axi_arprot),
    .m02_axi_arqos      (m02_axi_arqos),
    .m02_axi_arregion   (m02_axi_arregion),
    .m02_axi_aruser     (),
    .m02_axi_arvalid    (m02_axi_arvalid),
    .m02_axi_arready    (m02_axi_arready),
    .m02_axi_rid        (m02_axi_rid),
    .m02_axi_rdata      (m02_axi_rdata),
    .m02_axi_rresp      (m02_axi_rresp),
    .m02_axi_rlast      (m02_axi_rlast),
    .m02_axi_ruser      (1'b0),
    .m02_axi_rvalid     (m02_axi_rvalid),
    .m02_axi_rready     (m02_axi_rready),

    // ---- M03 ----
    .m03_axi_awid       (m03_axi_awid),
    .m03_axi_awaddr     (m03_axi_awaddr),
    .m03_axi_awlen      (m03_axi_awlen),
    .m03_axi_awsize     (m03_axi_awsize),
    .m03_axi_awburst    (m03_axi_awburst),
    .m03_axi_awlock     (m03_axi_awlock),
    .m03_axi_awcache    (m03_axi_awcache),
    .m03_axi_awprot     (m03_axi_awprot),
    .m03_axi_awqos      (m03_axi_awqos),
    .m03_axi_awregion   (m03_axi_awregion),
    .m03_axi_awuser     (),
    .m03_axi_awvalid    (m03_axi_awvalid),
    .m03_axi_awready    (m03_axi_awready),
    .m03_axi_wdata      (m03_axi_wdata),
    .m03_axi_wstrb      (m03_axi_wstrb),
    .m03_axi_wlast      (m03_axi_wlast),
    .m03_axi_wuser      (),
    .m03_axi_wvalid     (m03_axi_wvalid),
    .m03_axi_wready     (m03_axi_wready),
    .m03_axi_bid        (m03_axi_bid),
    .m03_axi_bresp      (m03_axi_bresp),
    .m03_axi_buser      (1'b0),
    .m03_axi_bvalid     (m03_axi_bvalid),
    .m03_axi_bready     (m03_axi_bready),
    .m03_axi_arid       (m03_axi_arid),
    .m03_axi_araddr     (m03_axi_araddr),
    .m03_axi_arlen      (m03_axi_arlen),
    .m03_axi_arsize     (m03_axi_arsize),
    .m03_axi_arburst    (m03_axi_arburst),
    .m03_axi_arlock     (m03_axi_arlock),
    .m03_axi_arcache    (m03_axi_arcache),
    .m03_axi_arprot     (m03_axi_arprot),
    .m03_axi_arqos      (m03_axi_arqos),
    .m03_axi_arregion   (m03_axi_arregion),
    .m03_axi_aruser     (),
    .m03_axi_arvalid    (m03_axi_arvalid),
    .m03_axi_arready    (m03_axi_arready),
    .m03_axi_rid        (m03_axi_rid),
    .m03_axi_rdata      (m03_axi_rdata),
    .m03_axi_rresp      (m03_axi_rresp),
    .m03_axi_rlast      (m03_axi_rlast),
    .m03_axi_ruser      (1'b0),
    .m03_axi_rvalid     (m03_axi_rvalid),
    .m03_axi_rready     (m03_axi_rready),

    // ---- M04 ----
    .m04_axi_awid       (m04_axi_awid),
    .m04_axi_awaddr     (m04_axi_awaddr),
    .m04_axi_awlen      (m04_axi_awlen),
    .m04_axi_awsize     (m04_axi_awsize),
    .m04_axi_awburst    (m04_axi_awburst),
    .m04_axi_awlock     (m04_axi_awlock),
    .m04_axi_awcache    (m04_axi_awcache),
    .m04_axi_awprot     (m04_axi_awprot),
    .m04_axi_awqos      (m04_axi_awqos),
    .m04_axi_awregion   (m04_axi_awregion),
    .m04_axi_awuser     (),
    .m04_axi_awvalid    (m04_axi_awvalid),
    .m04_axi_awready    (m04_axi_awready),
    .m04_axi_wdata      (m04_axi_wdata),
    .m04_axi_wstrb      (m04_axi_wstrb),
    .m04_axi_wlast      (m04_axi_wlast),
    .m04_axi_wuser      (),
    .m04_axi_wvalid     (m04_axi_wvalid),
    .m04_axi_wready     (m04_axi_wready),
    .m04_axi_bid        (m04_axi_bid),
    .m04_axi_bresp      (m04_axi_bresp),
    .m04_axi_buser      (1'b0),
    .m04_axi_bvalid     (m04_axi_bvalid),
    .m04_axi_bready     (m04_axi_bready),
    .m04_axi_arid       (m04_axi_arid),
    .m04_axi_araddr     (m04_axi_araddr),
    .m04_axi_arlen      (m04_axi_arlen),
    .m04_axi_arsize     (m04_axi_arsize),
    .m04_axi_arburst    (m04_axi_arburst),
    .m04_axi_arlock     (m04_axi_arlock),
    .m04_axi_arcache    (m04_axi_arcache),
    .m04_axi_arprot     (m04_axi_arprot),
    .m04_axi_arqos      (m04_axi_arqos),
    .m04_axi_arregion   (m04_axi_arregion),
    .m04_axi_aruser     (),
    .m04_axi_arvalid    (m04_axi_arvalid),
    .m04_axi_arready    (m04_axi_arready),
    .m04_axi_rid        (m04_axi_rid),
    .m04_axi_rdata      (m04_axi_rdata),
    .m04_axi_rresp      (m04_axi_rresp),
    .m04_axi_rlast      (m04_axi_rlast),
    .m04_axi_ruser      (1'b0),
    .m04_axi_rvalid     (m04_axi_rvalid),
    .m04_axi_rready     (m04_axi_rready),

    // ---- M05 ----
    .m05_axi_awid       (m05_axi_awid),
    .m05_axi_awaddr     (m05_axi_awaddr),
    .m05_axi_awlen      (m05_axi_awlen),
    .m05_axi_awsize     (m05_axi_awsize),
    .m05_axi_awburst    (m05_axi_awburst),
    .m05_axi_awlock     (m05_axi_awlock),
    .m05_axi_awcache    (m05_axi_awcache),
    .m05_axi_awprot     (m05_axi_awprot),
    .m05_axi_awqos      (m05_axi_awqos),
    .m05_axi_awregion   (m05_axi_awregion),
    .m05_axi_awuser     (),
    .m05_axi_awvalid    (m05_axi_awvalid),
    .m05_axi_awready    (m05_axi_awready),
    .m05_axi_wdata      (m05_axi_wdata),
    .m05_axi_wstrb      (m05_axi_wstrb),
    .m05_axi_wlast      (m05_axi_wlast),
    .m05_axi_wuser      (),
    .m05_axi_wvalid     (m05_axi_wvalid),
    .m05_axi_wready     (m05_axi_wready),
    .m05_axi_bid        (m05_axi_bid),
    .m05_axi_bresp      (m05_axi_bresp),
    .m05_axi_buser      (1'b0),
    .m05_axi_bvalid     (m05_axi_bvalid),
    .m05_axi_bready     (m05_axi_bready),
    .m05_axi_arid       (m05_axi_arid),
    .m05_axi_araddr     (m05_axi_araddr),
    .m05_axi_arlen      (m05_axi_arlen),
    .m05_axi_arsize     (m05_axi_arsize),
    .m05_axi_arburst    (m05_axi_arburst),
    .m05_axi_arlock     (m05_axi_arlock),
    .m05_axi_arcache    (m05_axi_arcache),
    .m05_axi_arprot     (m05_axi_arprot),
    .m05_axi_arqos      (m05_axi_arqos),
    .m05_axi_arregion   (m05_axi_arregion),
    .m05_axi_aruser     (),
    .m05_axi_arvalid    (m05_axi_arvalid),
    .m05_axi_arready    (m05_axi_arready),
    .m05_axi_rid        (m05_axi_rid),
    .m05_axi_rdata      (m05_axi_rdata),
    .m05_axi_rresp      (m05_axi_rresp),
    .m05_axi_rlast      (m05_axi_rlast),
    .m05_axi_ruser      (1'b0),
    .m05_axi_rvalid     (m05_axi_rvalid),
    .m05_axi_rready     (m05_axi_rready),

    // ---- M06 ----
    .m06_axi_awid       (m06_axi_awid),
    .m06_axi_awaddr     (m06_axi_awaddr),
    .m06_axi_awlen      (m06_axi_awlen),
    .m06_axi_awsize     (m06_axi_awsize),
    .m06_axi_awburst    (m06_axi_awburst),
    .m06_axi_awlock     (m06_axi_awlock),
    .m06_axi_awcache    (m06_axi_awcache),
    .m06_axi_awprot     (m06_axi_awprot),
    .m06_axi_awqos      (m06_axi_awqos),
    .m06_axi_awregion   (m06_axi_awregion),
    .m06_axi_awuser     (),
    .m06_axi_awvalid    (m06_axi_awvalid),
    .m06_axi_awready    (m06_axi_awready),
    .m06_axi_wdata      (m06_axi_wdata),
    .m06_axi_wstrb      (m06_axi_wstrb),
    .m06_axi_wlast      (m06_axi_wlast),
    .m06_axi_wuser      (),
    .m06_axi_wvalid     (m06_axi_wvalid),
    .m06_axi_wready     (m06_axi_wready),
    .m06_axi_bid        (m06_axi_bid),
    .m06_axi_bresp      (m06_axi_bresp),
    .m06_axi_buser      (1'b0),
    .m06_axi_bvalid     (m06_axi_bvalid),
    .m06_axi_bready     (m06_axi_bready),
    .m06_axi_arid       (m06_axi_arid),
    .m06_axi_araddr     (m06_axi_araddr),
    .m06_axi_arlen      (m06_axi_arlen),
    .m06_axi_arsize     (m06_axi_arsize),
    .m06_axi_arburst    (m06_axi_arburst),
    .m06_axi_arlock     (m06_axi_arlock),
    .m06_axi_arcache    (m06_axi_arcache),
    .m06_axi_arprot     (m06_axi_arprot),
    .m06_axi_arqos      (m06_axi_arqos),
    .m06_axi_arregion   (m06_axi_arregion),
    .m06_axi_aruser     (),
    .m06_axi_arvalid    (m06_axi_arvalid),
    .m06_axi_arready    (m06_axi_arready),
    .m06_axi_rid        (m06_axi_rid),
    .m06_axi_rdata      (m06_axi_rdata),
    .m06_axi_rresp      (m06_axi_rresp),
    .m06_axi_rlast      (m06_axi_rlast),
    .m06_axi_ruser      (1'b0),
    .m06_axi_rvalid     (m06_axi_rvalid),
    .m06_axi_rready     (m06_axi_rready),

    // ---- M07 ----
    .m07_axi_awid       (m07_axi_awid),
    .m07_axi_awaddr     (m07_axi_awaddr),
    .m07_axi_awlen      (m07_axi_awlen),
    .m07_axi_awsize     (m07_axi_awsize),
    .m07_axi_awburst    (m07_axi_awburst),
    .m07_axi_awlock     (m07_axi_awlock),
    .m07_axi_awcache    (m07_axi_awcache),
    .m07_axi_awprot     (m07_axi_awprot),
    .m07_axi_awqos      (m07_axi_awqos),
    .m07_axi_awregion   (m07_axi_awregion),
    .m07_axi_awuser     (),
    .m07_axi_awvalid    (m07_axi_awvalid),
    .m07_axi_awready    (m07_axi_awready),
    .m07_axi_wdata      (m07_axi_wdata),
    .m07_axi_wstrb      (m07_axi_wstrb),
    .m07_axi_wlast      (m07_axi_wlast),
    .m07_axi_wuser      (),
    .m07_axi_wvalid     (m07_axi_wvalid),
    .m07_axi_wready     (m07_axi_wready),
    .m07_axi_bid        (m07_axi_bid),
    .m07_axi_bresp      (m07_axi_bresp),
    .m07_axi_buser      (1'b0),
    .m07_axi_bvalid     (m07_axi_bvalid),
    .m07_axi_bready     (m07_axi_bready),
    .m07_axi_arid       (m07_axi_arid),
    .m07_axi_araddr     (m07_axi_araddr),
    .m07_axi_arlen      (m07_axi_arlen),
    .m07_axi_arsize     (m07_axi_arsize),
    .m07_axi_arburst    (m07_axi_arburst),
    .m07_axi_arlock     (m07_axi_arlock),
    .m07_axi_arcache    (m07_axi_arcache),
    .m07_axi_arprot     (m07_axi_arprot),
    .m07_axi_arqos      (m07_axi_arqos),
    .m07_axi_arregion   (m07_axi_arregion),
    .m07_axi_aruser     (),
    .m07_axi_arvalid    (m07_axi_arvalid),
    .m07_axi_arready    (m07_axi_arready),
    .m07_axi_rid        (m07_axi_rid),
    .m07_axi_rdata      (m07_axi_rdata),
    .m07_axi_rresp      (m07_axi_rresp),
    .m07_axi_rlast      (m07_axi_rlast),
    .m07_axi_ruser      (1'b0),
    .m07_axi_rvalid     (m07_axi_rvalid),
    .m07_axi_rready     (m07_axi_rready),

    // ---- M08 ----
    .m08_axi_awid       (m08_axi_awid),
    .m08_axi_awaddr     (m08_axi_awaddr),
    .m08_axi_awlen      (m08_axi_awlen),
    .m08_axi_awsize     (m08_axi_awsize),
    .m08_axi_awburst    (m08_axi_awburst),
    .m08_axi_awlock     (m08_axi_awlock),
    .m08_axi_awcache    (m08_axi_awcache),
    .m08_axi_awprot     (m08_axi_awprot),
    .m08_axi_awqos      (m08_axi_awqos),
    .m08_axi_awregion   (m08_axi_awregion),
    .m08_axi_awuser     (),
    .m08_axi_awvalid    (m08_axi_awvalid),
    .m08_axi_awready    (m08_axi_awready),
    .m08_axi_wdata      (m08_axi_wdata),
    .m08_axi_wstrb      (m08_axi_wstrb),
    .m08_axi_wlast      (m08_axi_wlast),
    .m08_axi_wuser      (),
    .m08_axi_wvalid     (m08_axi_wvalid),
    .m08_axi_wready     (m08_axi_wready),
    .m08_axi_bid        (m08_axi_bid),
    .m08_axi_bresp      (m08_axi_bresp),
    .m08_axi_buser      (1'b0),
    .m08_axi_bvalid     (m08_axi_bvalid),
    .m08_axi_bready     (m08_axi_bready),
    .m08_axi_arid       (m08_axi_arid),
    .m08_axi_araddr     (m08_axi_araddr),
    .m08_axi_arlen      (m08_axi_arlen),
    .m08_axi_arsize     (m08_axi_arsize),
    .m08_axi_arburst    (m08_axi_arburst),
    .m08_axi_arlock     (m08_axi_arlock),
    .m08_axi_arcache    (m08_axi_arcache),
    .m08_axi_arprot     (m08_axi_arprot),
    .m08_axi_arqos      (m08_axi_arqos),
    .m08_axi_arregion   (m08_axi_arregion),
    .m08_axi_aruser     (),
    .m08_axi_arvalid    (m08_axi_arvalid),
    .m08_axi_arready    (m08_axi_arready),
    .m08_axi_rid        (m08_axi_rid),
    .m08_axi_rdata      (m08_axi_rdata),
    .m08_axi_rresp      (m08_axi_rresp),
    .m08_axi_rlast      (m08_axi_rlast),
    .m08_axi_ruser      (1'b0),
    .m08_axi_rvalid     (m08_axi_rvalid),
    .m08_axi_rready     (m08_axi_rready),

    // ---- M09 ----
    .m09_axi_awid       (m09_axi_awid),
    .m09_axi_awaddr     (m09_axi_awaddr),
    .m09_axi_awlen      (m09_axi_awlen),
    .m09_axi_awsize     (m09_axi_awsize),
    .m09_axi_awburst    (m09_axi_awburst),
    .m09_axi_awlock     (m09_axi_awlock),
    .m09_axi_awcache    (m09_axi_awcache),
    .m09_axi_awprot     (m09_axi_awprot),
    .m09_axi_awqos      (m09_axi_awqos),
    .m09_axi_awregion   (m09_axi_awregion),
    .m09_axi_awuser     (),
    .m09_axi_awvalid    (m09_axi_awvalid),
    .m09_axi_awready    (m09_axi_awready),
    .m09_axi_wdata      (m09_axi_wdata),
    .m09_axi_wstrb      (m09_axi_wstrb),
    .m09_axi_wlast      (m09_axi_wlast),
    .m09_axi_wuser      (),
    .m09_axi_wvalid     (m09_axi_wvalid),
    .m09_axi_wready     (m09_axi_wready),
    .m09_axi_bid        (m09_axi_bid),
    .m09_axi_bresp      (m09_axi_bresp),
    .m09_axi_buser      (1'b0),
    .m09_axi_bvalid     (m09_axi_bvalid),
    .m09_axi_bready     (m09_axi_bready),
    .m09_axi_arid       (m09_axi_arid),
    .m09_axi_araddr     (m09_axi_araddr),
    .m09_axi_arlen      (m09_axi_arlen),
    .m09_axi_arsize     (m09_axi_arsize),
    .m09_axi_arburst    (m09_axi_arburst),
    .m09_axi_arlock     (m09_axi_arlock),
    .m09_axi_arcache    (m09_axi_arcache),
    .m09_axi_arprot     (m09_axi_arprot),
    .m09_axi_arqos      (m09_axi_arqos),
    .m09_axi_arregion   (m09_axi_arregion),
    .m09_axi_aruser     (),
    .m09_axi_arvalid    (m09_axi_arvalid),
    .m09_axi_arready    (m09_axi_arready),
    .m09_axi_rid        (m09_axi_rid),
    .m09_axi_rdata      (m09_axi_rdata),
    .m09_axi_rresp      (m09_axi_rresp),
    .m09_axi_rlast      (m09_axi_rlast),
    .m09_axi_ruser      (1'b0),
    .m09_axi_rvalid     (m09_axi_rvalid),
    .m09_axi_rready     (m09_axi_rready),

    // ---- M10 ----
    .m10_axi_awid       (m10_axi_awid),
    .m10_axi_awaddr     (m10_axi_awaddr),
    .m10_axi_awlen      (m10_axi_awlen),
    .m10_axi_awsize     (m10_axi_awsize),
    .m10_axi_awburst    (m10_axi_awburst),
    .m10_axi_awlock     (m10_axi_awlock),
    .m10_axi_awcache    (m10_axi_awcache),
    .m10_axi_awprot     (m10_axi_awprot),
    .m10_axi_awqos      (m10_axi_awqos),
    .m10_axi_awregion   (m10_axi_awregion),
    .m10_axi_awuser     (),
    .m10_axi_awvalid    (m10_axi_awvalid),
    .m10_axi_awready    (m10_axi_awready),
    .m10_axi_wdata      (m10_axi_wdata),
    .m10_axi_wstrb      (m10_axi_wstrb),
    .m10_axi_wlast      (m10_axi_wlast),
    .m10_axi_wuser      (),
    .m10_axi_wvalid     (m10_axi_wvalid),
    .m10_axi_wready     (m10_axi_wready),
    .m10_axi_bid        (m10_axi_bid),
    .m10_axi_bresp      (m10_axi_bresp),
    .m10_axi_buser      (1'b0),
    .m10_axi_bvalid     (m10_axi_bvalid),
    .m10_axi_bready     (m10_axi_bready),
    .m10_axi_arid       (m10_axi_arid),
    .m10_axi_araddr     (m10_axi_araddr),
    .m10_axi_arlen      (m10_axi_arlen),
    .m10_axi_arsize     (m10_axi_arsize),
    .m10_axi_arburst    (m10_axi_arburst),
    .m10_axi_arlock     (m10_axi_arlock),
    .m10_axi_arcache    (m10_axi_arcache),
    .m10_axi_arprot     (m10_axi_arprot),
    .m10_axi_arqos      (m10_axi_arqos),
    .m10_axi_arregion   (m10_axi_arregion),
    .m10_axi_aruser     (),
    .m10_axi_arvalid    (m10_axi_arvalid),
    .m10_axi_arready    (m10_axi_arready),
    .m10_axi_rid        (m10_axi_rid),
    .m10_axi_rdata      (m10_axi_rdata),
    .m10_axi_rresp      (m10_axi_rresp),
    .m10_axi_rlast      (m10_axi_rlast),
    .m10_axi_ruser      (1'b0),
    .m10_axi_rvalid     (m10_axi_rvalid),
    .m10_axi_rready     (m10_axi_rready)
);

// =============================================================================
// IP Block Instantiations
// =============================================================================

// ---- S00: VeeR EL2 CPU ----
veer_el2_top #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    .BOOT_ADDR  (32'h3000_0000)
) u_veer (
    .clk            (clk),
    .rst_l          (~sys_reset_active),
    .ar_irq         (ar_irq),
    .ext_int        (cpu_ext_int),
    .m_axi_awid     (s00_axi_awid),
    .m_axi_awaddr   (s00_axi_awaddr),
    .m_axi_awlen    (s00_axi_awlen),
    .m_axi_awsize   (s00_axi_awsize),
    .m_axi_awburst  (s00_axi_awburst),
    .m_axi_awlock   (s00_axi_awlock),
    .m_axi_awcache  (s00_axi_awcache),
    .m_axi_awprot   (s00_axi_awprot),
    .m_axi_awqos    (s00_axi_awqos),
    .m_axi_awvalid  (s00_axi_awvalid),
    .m_axi_awready  (s00_axi_awready),
    .m_axi_wdata    (s00_axi_wdata),
    .m_axi_wstrb    (s00_axi_wstrb),
    .m_axi_wlast    (s00_axi_wlast),
    .m_axi_wvalid   (s00_axi_wvalid),
    .m_axi_wready   (s00_axi_wready),
    .m_axi_bid      (s00_axi_bid),
    .m_axi_bresp    (s00_axi_bresp),
    .m_axi_bvalid   (s00_axi_bvalid),
    .m_axi_bready   (s00_axi_bready),
    .m_axi_arid     (s00_axi_arid),
    .m_axi_araddr   (s00_axi_araddr),
    .m_axi_arlen    (s00_axi_arlen),
    .m_axi_arsize   (s00_axi_arsize),
    .m_axi_arburst  (s00_axi_arburst),
    .m_axi_arlock   (s00_axi_arlock),
    .m_axi_arcache  (s00_axi_arcache),
    .m_axi_arprot   (s00_axi_arprot),
    .m_axi_arqos    (s00_axi_arqos),
    .m_axi_arvalid  (s00_axi_arvalid),
    .m_axi_arready  (s00_axi_arready),
    .m_axi_rid      (s00_axi_rid),
    .m_axi_rdata    (s00_axi_rdata),
    .m_axi_rresp    (s00_axi_rresp),
    .m_axi_rlast    (s00_axi_rlast),
    .m_axi_rvalid   (s00_axi_rvalid),
    .m_axi_rready   (s00_axi_rready)
);

// ---- S01: AR Read Master ----
ar_read_master #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_ar_read (
    .clk            (clk),
    .rst            (sys_reset_active),
    .start          (ar_rm_start),
    .base_addr      (ar_rm_base_addr),
    .beat_count     (ar_rm_beat_count),
    .busy           (ar_rm_busy),
    .done           (ar_rm_done),
    .rdata          (ar_rm_rdata),
    .rvalid_out     (ar_rm_rvalid),
    .m_axi_awid     (s01_axi_awid),
    .m_axi_awaddr   (s01_axi_awaddr),
    .m_axi_awlen    (s01_axi_awlen),
    .m_axi_awsize   (s01_axi_awsize),
    .m_axi_awburst  (s01_axi_awburst),
    .m_axi_awlock   (s01_axi_awlock),
    .m_axi_awcache  (s01_axi_awcache),
    .m_axi_awprot   (s01_axi_awprot),
    .m_axi_awqos    (s01_axi_awqos),
    .m_axi_awvalid  (s01_axi_awvalid),
    .m_axi_awready  (s01_axi_awready),
    .m_axi_wdata    (s01_axi_wdata),
    .m_axi_wstrb    (s01_axi_wstrb),
    .m_axi_wlast    (s01_axi_wlast),
    .m_axi_wvalid   (s01_axi_wvalid),
    .m_axi_wready   (s01_axi_wready),
    .m_axi_bid      (s01_axi_bid),
    .m_axi_bresp    (s01_axi_bresp),
    .m_axi_bvalid   (s01_axi_bvalid),
    .m_axi_bready   (s01_axi_bready),
    .m_axi_arid     (s01_axi_arid),
    .m_axi_araddr   (s01_axi_araddr),
    .m_axi_arlen    (s01_axi_arlen),
    .m_axi_arsize   (s01_axi_arsize),
    .m_axi_arburst  (s01_axi_arburst),
    .m_axi_arlock   (s01_axi_arlock),
    .m_axi_arcache  (s01_axi_arcache),
    .m_axi_arprot   (s01_axi_arprot),
    .m_axi_arqos    (s01_axi_arqos),
    .m_axi_arvalid  (s01_axi_arvalid),
    .m_axi_arready  (s01_axi_arready),
    .m_axi_rid      (s01_axi_rid),
    .m_axi_rdata    (s01_axi_rdata),
    .m_axi_rresp    (s01_axi_rresp),
    .m_axi_rlast    (s01_axi_rlast),
    .m_axi_rvalid   (s01_axi_rvalid),
    .m_axi_rready   (s01_axi_rready)
);

// ---- S02: AR Write Master ----
ar_write_master #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_ar_write (
    .clk            (clk),
    .rst            (sys_reset_active),
    .pixel_data     (ar_wm_pixel_data),
    .pixel_addr     (ar_wm_pixel_addr),
    .pixel_valid    (ar_wm_pixel_valid),
    .pixel_ready    (ar_wm_pixel_ready),
    .busy           (ar_wm_busy),
    .done           (ar_wm_done),
    .m_axi_arid     (s02_axi_arid),
    .m_axi_araddr   (s02_axi_araddr),
    .m_axi_arlen    (s02_axi_arlen),
    .m_axi_arsize   (s02_axi_arsize),
    .m_axi_arburst  (s02_axi_arburst),
    .m_axi_arlock   (s02_axi_arlock),
    .m_axi_arcache  (s02_axi_arcache),
    .m_axi_arprot   (s02_axi_arprot),
    .m_axi_arqos    (s02_axi_arqos),
    .m_axi_arvalid  (s02_axi_arvalid),
    .m_axi_arready  (s02_axi_arready),
    .m_axi_rid      (s02_axi_rid),
    .m_axi_rdata    (s02_axi_rdata),
    .m_axi_rresp    (s02_axi_rresp),
    .m_axi_rlast    (s02_axi_rlast),
    .m_axi_rvalid   (s02_axi_rvalid),
    .m_axi_rready   (s02_axi_rready),
    .m_axi_awid     (s02_axi_awid),
    .m_axi_awaddr   (s02_axi_awaddr),
    .m_axi_awlen    (s02_axi_awlen),
    .m_axi_awsize   (s02_axi_awsize),
    .m_axi_awburst  (s02_axi_awburst),
    .m_axi_awlock   (s02_axi_awlock),
    .m_axi_awcache  (s02_axi_awcache),
    .m_axi_awprot   (s02_axi_awprot),
    .m_axi_awqos    (s02_axi_awqos),
    .m_axi_awvalid  (s02_axi_awvalid),
    .m_axi_awready  (s02_axi_awready),
    .m_axi_wdata    (s02_axi_wdata),
    .m_axi_wstrb    (s02_axi_wstrb),
    .m_axi_wlast    (s02_axi_wlast),
    .m_axi_wvalid   (s02_axi_wvalid),
    .m_axi_wready   (s02_axi_wready),
    .m_axi_bid      (s02_axi_bid),
    .m_axi_bresp    (s02_axi_bresp),
    .m_axi_bvalid   (s02_axi_bvalid),
    .m_axi_bready   (s02_axi_bready)
);

// ---- S03: VGA Controller ----
vga_controller #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_vga (
    .clk            (clk),
    .rst            (sys_reset_active),
    .vga_en         (vga_en),
    .fb_base        (vga_fb_base),
    .fb_stride      (vga_fb_stride),
    .vsync_pol      (vsync_pol),
    .hsync_pol      (hsync_pol),
    .h_total        (h_total),
    .h_active       (h_active),
    .v_total        (v_total),
    .v_active       (v_active),
    .h_sync_start   (h_sync_start),
    .h_sync_end     (h_sync_end),
    .v_sync_start   (v_sync_start),
    .v_sync_end     (v_sync_end),
    .vga_hsync      (vga_hsync),
    .vga_vsync      (vga_vsync),
    .vga_r          (vga_r),
    .vga_g          (vga_g),
    .vga_b          (vga_b),
    .vga_blank_n    (vga_blank_n),
    .vga_sync_n     (vga_sync_n),
    .vga_clk_out    (vga_clk_out),
    .vsync_active   (vsync_active),
    .hsync_active   (hsync_active),
    .m_axi_awid     (s03_axi_awid),
    .m_axi_awaddr   (s03_axi_awaddr),
    .m_axi_awlen    (s03_axi_awlen),
    .m_axi_awsize   (s03_axi_awsize),
    .m_axi_awburst  (s03_axi_awburst),
    .m_axi_awlock   (s03_axi_awlock),
    .m_axi_awcache  (s03_axi_awcache),
    .m_axi_awprot   (s03_axi_awprot),
    .m_axi_awqos    (s03_axi_awqos),
    .m_axi_awvalid  (s03_axi_awvalid),
    .m_axi_awready  (s03_axi_awready),
    .m_axi_wdata    (s03_axi_wdata),
    .m_axi_wstrb    (s03_axi_wstrb),
    .m_axi_wlast    (s03_axi_wlast),
    .m_axi_wvalid   (s03_axi_wvalid),
    .m_axi_wready   (s03_axi_wready),
    .m_axi_bid      (s03_axi_bid),
    .m_axi_bresp    (s03_axi_bresp),
    .m_axi_bvalid   (s03_axi_bvalid),
    .m_axi_bready   (s03_axi_bready),
    .m_axi_arid     (s03_axi_arid),
    .m_axi_araddr   (s03_axi_araddr),
    .m_axi_arlen    (s03_axi_arlen),
    .m_axi_arsize   (s03_axi_arsize),
    .m_axi_arburst  (s03_axi_arburst),
    .m_axi_arlock   (s03_axi_arlock),
    .m_axi_arcache  (s03_axi_arcache),
    .m_axi_arprot   (s03_axi_arprot),
    .m_axi_arqos    (s03_axi_arqos),
    .m_axi_arvalid  (s03_axi_arvalid),
    .m_axi_arready  (s03_axi_arready),
    .m_axi_rid      (s03_axi_rid),
    .m_axi_rdata    (s03_axi_rdata),
    .m_axi_rresp    (s03_axi_rresp),
    .m_axi_rlast    (s03_axi_rlast),
    .m_axi_rvalid   (s03_axi_rvalid),
    .m_axi_rready   (s03_axi_rready)
);

// ---- M00: Data Memory ----
data_mem #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_data_mem (
    .clk            (clk),
    .rst            (sys_reset_active),
    .s_axi_awid     (m00_axi_awid),
    .s_axi_awaddr   (m00_axi_awaddr),
    .s_axi_awlen    (m00_axi_awlen),
    .s_axi_awsize   (m00_axi_awsize),
    .s_axi_awburst  (m00_axi_awburst),
    .s_axi_awlock   (m00_axi_awlock),
    .s_axi_awcache  (m00_axi_awcache),
    .s_axi_awprot   (m00_axi_awprot),
    .s_axi_awqos    (m00_axi_awqos),
    .s_axi_awregion (m00_axi_awregion),
    .s_axi_awvalid  (m00_axi_awvalid),
    .s_axi_awready  (m00_axi_awready),
    .s_axi_wdata    (m00_axi_wdata),
    .s_axi_wstrb    (m00_axi_wstrb),
    .s_axi_wlast    (m00_axi_wlast),
    .s_axi_wvalid   (m00_axi_wvalid),
    .s_axi_wready   (m00_axi_wready),
    .s_axi_bid      (m00_axi_bid),
    .s_axi_bresp    (m00_axi_bresp),
    .s_axi_bvalid   (m00_axi_bvalid),
    .s_axi_bready   (m00_axi_bready),
    .s_axi_arid     (m00_axi_arid),
    .s_axi_araddr   (m00_axi_araddr),
    .s_axi_arlen    (m00_axi_arlen),
    .s_axi_arsize   (m00_axi_arsize),
    .s_axi_arburst  (m00_axi_arburst),
    .s_axi_arlock   (m00_axi_arlock),
    .s_axi_arcache  (m00_axi_arcache),
    .s_axi_arprot   (m00_axi_arprot),
    .s_axi_arqos    (m00_axi_arqos),
    .s_axi_arregion (m00_axi_arregion),
    .s_axi_arvalid  (m00_axi_arvalid),
    .s_axi_arready  (m00_axi_arready),
    .s_axi_rid      (m00_axi_rid),
    .s_axi_rdata    (m00_axi_rdata),
    .s_axi_rresp    (m00_axi_rresp),
    .s_axi_rlast    (m00_axi_rlast),
    .s_axi_rvalid   (m00_axi_rvalid),
    .s_axi_rready   (m00_axi_rready)
);

// ---- M01: Framebuffer ----
framebuffer #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_framebuffer (
    .clk            (clk),
    .rst            (sys_reset_active),
    .s_axi_awid     (m01_axi_awid),
    .s_axi_awaddr   (m01_axi_awaddr),
    .s_axi_awlen    (m01_axi_awlen),
    .s_axi_awsize   (m01_axi_awsize),
    .s_axi_awburst  (m01_axi_awburst),
    .s_axi_awlock   (m01_axi_awlock),
    .s_axi_awcache  (m01_axi_awcache),
    .s_axi_awprot   (m01_axi_awprot),
    .s_axi_awqos    (m01_axi_awqos),
    .s_axi_awregion (m01_axi_awregion),
    .s_axi_awvalid  (m01_axi_awvalid),
    .s_axi_awready  (m01_axi_awready),
    .s_axi_wdata    (m01_axi_wdata),
    .s_axi_wstrb    (m01_axi_wstrb),
    .s_axi_wlast    (m01_axi_wlast),
    .s_axi_wvalid   (m01_axi_wvalid),
    .s_axi_wready   (m01_axi_wready),
    .s_axi_bid      (m01_axi_bid),
    .s_axi_bresp    (m01_axi_bresp),
    .s_axi_bvalid   (m01_axi_bvalid),
    .s_axi_bready   (m01_axi_bready),
    .s_axi_arid     (m01_axi_arid),
    .s_axi_araddr   (m01_axi_araddr),
    .s_axi_arlen    (m01_axi_arlen),
    .s_axi_arsize   (m01_axi_arsize),
    .s_axi_arburst  (m01_axi_arburst),
    .s_axi_arlock   (m01_axi_arlock),
    .s_axi_arcache  (m01_axi_arcache),
    .s_axi_arprot   (m01_axi_arprot),
    .s_axi_arqos    (m01_axi_arqos),
    .s_axi_arregion (m01_axi_arregion),
    .s_axi_arvalid  (m01_axi_arvalid),
    .s_axi_arready  (m01_axi_arready),
    .s_axi_rid      (m01_axi_rid),
    .s_axi_rdata    (m01_axi_rdata),
    .s_axi_rresp    (m01_axi_rresp),
    .s_axi_rlast    (m01_axi_rlast),
    .s_axi_rvalid   (m01_axi_rvalid),
    .s_axi_rready   (m01_axi_rready)
);

// ---- M02: AR Control ----
ar_control #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_ar_ctrl (
    .clk            (clk),
    .rst            (sys_reset_active),
    .s_axi_awid     (m02_axi_awid),
    .s_axi_awaddr   (m02_axi_awaddr),
    .s_axi_awlen    (m02_axi_awlen),
    .s_axi_awsize   (m02_axi_awsize),
    .s_axi_awburst  (m02_axi_awburst),
    .s_axi_awlock   (m02_axi_awlock),
    .s_axi_awcache  (m02_axi_awcache),
    .s_axi_awprot   (m02_axi_awprot),
    .s_axi_awqos    (m02_axi_awqos),
    .s_axi_awregion (m02_axi_awregion),
    .s_axi_awvalid  (m02_axi_awvalid),
    .s_axi_awready  (m02_axi_awready),
    .s_axi_wdata    (m02_axi_wdata),
    .s_axi_wstrb    (m02_axi_wstrb),
    .s_axi_wlast    (m02_axi_wlast),
    .s_axi_wvalid   (m02_axi_wvalid),
    .s_axi_wready   (m02_axi_wready),
    .s_axi_bid      (m02_axi_bid),
    .s_axi_bresp    (m02_axi_bresp),
    .s_axi_bvalid   (m02_axi_bvalid),
    .s_axi_bready   (m02_axi_bready),
    .s_axi_arid     (m02_axi_arid),
    .s_axi_araddr   (m02_axi_araddr),
    .s_axi_arlen    (m02_axi_arlen),
    .s_axi_arsize   (m02_axi_arsize),
    .s_axi_arburst  (m02_axi_arburst),
    .s_axi_arlock   (m02_axi_arlock),
    .s_axi_arcache  (m02_axi_arcache),
    .s_axi_arprot   (m02_axi_arprot),
    .s_axi_arqos    (m02_axi_arqos),
    .s_axi_arregion (m02_axi_arregion),
    .s_axi_arvalid  (m02_axi_arvalid),
    .s_axi_arready  (m02_axi_arready),
    .s_axi_rid      (m02_axi_rid),
    .s_axi_rdata    (m02_axi_rdata),
    .s_axi_rresp    (m02_axi_rresp),
    .s_axi_rlast    (m02_axi_rlast),
    .s_axi_rvalid   (m02_axi_rvalid),
    .s_axi_rready   (m02_axi_rready),
    .ar_start       (ar_start),
    .ar_reset       (ar_reset),
    .ar_prim_type   (ar_prim_type),
    .ar_prim_base   (ar_prim_base),
    .ar_prim_count  (ar_prim_count),
    .ar_color       (ar_color),
    .ar_fb_base     (ar_fb_base_ctrl),
    .ar_fb_stride   (ar_fb_stride_ctrl),
    .ar_busy        (ar_busy),
    .ar_done        (ar_done),
    .ar_error       (ar_error),
    .irq            (ar_irq)
);

// ---- M03: HPM ----
hpm #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_hpm (
    .clk                (clk),
    .rst                (sys_reset_active),
    .s_axi_awid         (m03_axi_awid),
    .s_axi_awaddr       (m03_axi_awaddr),
    .s_axi_awlen        (m03_axi_awlen),
    .s_axi_awsize       (m03_axi_awsize),
    .s_axi_awburst      (m03_axi_awburst),
    .s_axi_awlock       (m03_axi_awlock),
    .s_axi_awcache      (m03_axi_awcache),
    .s_axi_awprot       (m03_axi_awprot),
    .s_axi_awqos        (m03_axi_awqos),
    .s_axi_awregion     (m03_axi_awregion),
    .s_axi_awvalid      (m03_axi_awvalid),
    .s_axi_awready      (m03_axi_awready),
    .s_axi_wdata        (m03_axi_wdata),
    .s_axi_wstrb        (m03_axi_wstrb),
    .s_axi_wlast        (m03_axi_wlast),
    .s_axi_wvalid       (m03_axi_wvalid),
    .s_axi_wready       (m03_axi_wready),
    .s_axi_bid          (m03_axi_bid),
    .s_axi_bresp        (m03_axi_bresp),
    .s_axi_bvalid       (m03_axi_bvalid),
    .s_axi_bready       (m03_axi_bready),
    .s_axi_arid         (m03_axi_arid),
    .s_axi_araddr       (m03_axi_araddr),
    .s_axi_arlen        (m03_axi_arlen),
    .s_axi_arsize       (m03_axi_arsize),
    .s_axi_arburst      (m03_axi_arburst),
    .s_axi_arlock       (m03_axi_arlock),
    .s_axi_arcache      (m03_axi_arcache),
    .s_axi_arprot       (m03_axi_arprot),
    .s_axi_arqos        (m03_axi_arqos),
    .s_axi_arregion     (m03_axi_arregion),
    .s_axi_arvalid      (m03_axi_arvalid),
    .s_axi_arready      (m03_axi_arready),
    .s_axi_rid          (m03_axi_rid),
    .s_axi_rdata        (m03_axi_rdata),
    .s_axi_rresp        (m03_axi_rresp),
    .s_axi_rlast        (m03_axi_rlast),
    .s_axi_rvalid       (m03_axi_rvalid),
    .s_axi_rready       (m03_axi_rready),
    .ev_mem_read        (ev_mem_read),
    .ev_mem_write       (ev_mem_write),
    .ev_pixel_out       (ev_pixel_out),
    .ev_ar_active       (ev_ar_active),
    .ev_setup           (ev_setup),
    .ev_irq_handling    (ev_irq_handling)
);

// ---- M04: VGA Ctrl Regs ----
vga_ctrl_regs #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_vga_regs (
    .clk            (clk),
    .rst            (sys_reset_active),
    .s_axi_awid     (m04_axi_awid),
    .s_axi_awaddr   (m04_axi_awaddr),
    .s_axi_awlen    (m04_axi_awlen),
    .s_axi_awsize   (m04_axi_awsize),
    .s_axi_awburst  (m04_axi_awburst),
    .s_axi_awlock   (m04_axi_awlock),
    .s_axi_awcache  (m04_axi_awcache),
    .s_axi_awprot   (m04_axi_awprot),
    .s_axi_awqos    (m04_axi_awqos),
    .s_axi_awregion (m04_axi_awregion),
    .s_axi_awvalid  (m04_axi_awvalid),
    .s_axi_awready  (m04_axi_awready),
    .s_axi_wdata    (m04_axi_wdata),
    .s_axi_wstrb    (m04_axi_wstrb),
    .s_axi_wlast    (m04_axi_wlast),
    .s_axi_wvalid   (m04_axi_wvalid),
    .s_axi_wready   (m04_axi_wready),
    .s_axi_bid      (m04_axi_bid),
    .s_axi_bresp    (m04_axi_bresp),
    .s_axi_bvalid   (m04_axi_bvalid),
    .s_axi_bready   (m04_axi_bready),
    .s_axi_arid     (m04_axi_arid),
    .s_axi_araddr   (m04_axi_araddr),
    .s_axi_arlen    (m04_axi_arlen),
    .s_axi_arsize   (m04_axi_arsize),
    .s_axi_arburst  (m04_axi_arburst),
    .s_axi_arlock   (m04_axi_arlock),
    .s_axi_arcache  (m04_axi_arcache),
    .s_axi_arprot   (m04_axi_arprot),
    .s_axi_arqos    (m04_axi_arqos),
    .s_axi_arregion (m04_axi_arregion),
    .s_axi_arvalid  (m04_axi_arvalid),
    .s_axi_arready  (m04_axi_arready),
    .s_axi_rid      (m04_axi_rid),
    .s_axi_rdata    (m04_axi_rdata),
    .s_axi_rresp    (m04_axi_rresp),
    .s_axi_rlast    (m04_axi_rlast),
    .s_axi_rvalid   (m04_axi_rvalid),
    .s_axi_rready   (m04_axi_rready),
    .vga_en         (vga_en),
    .vsync_pol      (vsync_pol),
    .hsync_pol      (hsync_pol),
    .h_total        (h_total),
    .h_active       (h_active),
    .v_total        (v_total),
    .v_active       (v_active),
    .h_sync_start   (h_sync_start),
    .h_sync_end     (h_sync_end),
    .v_sync_start   (v_sync_start),
    .v_sync_end     (v_sync_end),
    .vga_fb_base    (vga_fb_base),
    .vga_fb_stride  (vga_fb_stride),
    .vsync_active   (vsync_active),
    .hsync_active   (hsync_active)
);

// ---- M05: AXI-Lite UART ----
axi_uart_top u_uart (
    .fixed_clk_i    (clk),
    .axi_aclk_i     (clk),
    .axi_aresetn_i  (~sys_reset_active),

    .axi_awid_i     ({{(12-ID_WIDTH){1'b0}}, m05_axi_awid}),
    .axi_awaddr_i   (m05_axi_awaddr[4:0]),
    .axi_awvalid_i  (m05_axi_awvalid),
    .axi_awready_o  (m05_axi_awready),

    .axi_wdata_i    (m05_axi_wdata),
    .axi_wstrb_i    (m05_axi_wstrb),
    .axi_wvalid_i   (m05_axi_wvalid),
    .axi_wready_o   (m05_axi_wready),

    .axi_bid_o      (m05_uart_bid_full),
    .axi_bresp_o    (m05_axi_bresp),
    .axi_bvalid_o   (m05_axi_bvalid),
    .axi_bready_i   (m05_axi_bready),

    .axi_arid_i     ({{(12-ID_WIDTH){1'b0}}, m05_axi_arid}),
    .axi_araddr_i   (m05_axi_araddr[4:0]),
    .axi_arvalid_i  (m05_axi_arvalid),
    .axi_arready_o  (m05_axi_arready),

    .axi_rid_o      (m05_uart_rid_full),
    .axi_rdata_o    (m05_axi_rdata),
    .axi_rresp_o    (m05_axi_rresp),
    .axi_rvalid_o   (m05_axi_rvalid),
    .axi_rready_i   (m05_axi_rready),

    .read_interrupt_o (uart_irq),
    .uart_tx_o      (uart_tx),
    .uart_rx_i      (uart_rx)
);
// ---- M06: gpio ----
gpio #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    .GPIO_WIDTH (32)
) u_gpio (
    .clk            (clk),
    .rst            (sys_reset_active),
    .s_axi_awid     (m06_axi_awid),
    .s_axi_awaddr   (m06_axi_awaddr),
    .s_axi_awlen    (m06_axi_awlen),
    .s_axi_awsize   (m06_axi_awsize),
    .s_axi_awburst  (m06_axi_awburst),
    .s_axi_awlock   (m06_axi_awlock),
    .s_axi_awcache  (m06_axi_awcache),
    .s_axi_awprot   (m06_axi_awprot),
    .s_axi_awqos    (m06_axi_awqos),
    .s_axi_awregion (m06_axi_awregion),
    .s_axi_awvalid  (m06_axi_awvalid),
    .s_axi_awready  (m06_axi_awready),
    .s_axi_wdata    (m06_axi_wdata),
    .s_axi_wstrb    (m06_axi_wstrb),
    .s_axi_wlast    (m06_axi_wlast),
    .s_axi_wvalid   (m06_axi_wvalid),
    .s_axi_wready   (m06_axi_wready),
    .s_axi_bid      (m06_axi_bid),
    .s_axi_bresp    (m06_axi_bresp),
    .s_axi_bvalid   (m06_axi_bvalid),
    .s_axi_bready   (m06_axi_bready),
    .s_axi_arid     (m06_axi_arid),
    .s_axi_araddr   (m06_axi_araddr),
    .s_axi_arlen    (m06_axi_arlen),
    .s_axi_arsize   (m06_axi_arsize),
    .s_axi_arburst  (m06_axi_arburst),
    .s_axi_arlock   (m06_axi_arlock),
    .s_axi_arcache  (m06_axi_arcache),
    .s_axi_arprot   (m06_axi_arprot),
    .s_axi_arqos    (m06_axi_arqos),
    .s_axi_arregion (m06_axi_arregion),
    .s_axi_arvalid  (m06_axi_arvalid),
    .s_axi_arready  (m06_axi_arready),
    .s_axi_rid      (m06_axi_rid),
    .s_axi_rdata    (m06_axi_rdata),
    .s_axi_rresp    (m06_axi_rresp),
    .s_axi_rlast    (m06_axi_rlast),
    .s_axi_rvalid   (m06_axi_rvalid),
    .s_axi_rready   (m06_axi_rready),
    .gpio_out       (gpio_out),
    .gpio_in        (gpio_in),
    .gpio_irq       (gpio_irq)
);
// ---- M07: spi ----
spi #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_spi (
    .clk            (clk),
    .rst            (sys_reset_active),
    .s_axi_awid     (m07_axi_awid),
    .s_axi_awaddr   (m07_axi_awaddr),
    .s_axi_awlen    (m07_axi_awlen),
    .s_axi_awsize   (m07_axi_awsize),
    .s_axi_awburst  (m07_axi_awburst),
    .s_axi_awlock   (m07_axi_awlock),
    .s_axi_awcache  (m07_axi_awcache),
    .s_axi_awprot   (m07_axi_awprot),
    .s_axi_awqos    (m07_axi_awqos),
    .s_axi_awregion (m07_axi_awregion),
    .s_axi_awvalid  (m07_axi_awvalid),
    .s_axi_awready  (m07_axi_awready),
    .s_axi_wdata    (m07_axi_wdata),
    .s_axi_wstrb    (m07_axi_wstrb),
    .s_axi_wlast    (m07_axi_wlast),
    .s_axi_wvalid   (m07_axi_wvalid),
    .s_axi_wready   (m07_axi_wready),
    .s_axi_bid      (m07_axi_bid),
    .s_axi_bresp    (m07_axi_bresp),
    .s_axi_bvalid   (m07_axi_bvalid),
    .s_axi_bready   (m07_axi_bready),
    .s_axi_arid     (m07_axi_arid),
    .s_axi_araddr   (m07_axi_araddr),
    .s_axi_arlen    (m07_axi_arlen),
    .s_axi_arsize   (m07_axi_arsize),
    .s_axi_arburst  (m07_axi_arburst),
    .s_axi_arlock   (m07_axi_arlock),
    .s_axi_arcache  (m07_axi_arcache),
    .s_axi_arprot   (m07_axi_arprot),
    .s_axi_arqos    (m07_axi_arqos),
    .s_axi_arregion (m07_axi_arregion),
    .s_axi_arvalid  (m07_axi_arvalid),
    .s_axi_arready  (m07_axi_arready),
    .s_axi_rid      (m07_axi_rid),
    .s_axi_rdata    (m07_axi_rdata),
    .s_axi_rresp    (m07_axi_rresp),
    .s_axi_rlast    (m07_axi_rlast),
    .s_axi_rvalid   (m07_axi_rvalid),
    .s_axi_rready   (m07_axi_rready),
    .spi_sclk       (spi_sclk),
    .spi_mosi       (spi_mosi),
    .spi_miso       (spi_miso),
    .spi_cs_n       (spi_cs_n),
    .spi_irq        (spi_irq)
);
// ---- M08: timer ----
timer #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_timer (
    .clk            (clk),
    .rst            (sys_reset_active),
    .s_axi_awid     (m08_axi_awid),
    .s_axi_awaddr   (m08_axi_awaddr),
    .s_axi_awlen    (m08_axi_awlen),
    .s_axi_awsize   (m08_axi_awsize),
    .s_axi_awburst  (m08_axi_awburst),
    .s_axi_awlock   (m08_axi_awlock),
    .s_axi_awcache  (m08_axi_awcache),
    .s_axi_awprot   (m08_axi_awprot),
    .s_axi_awqos    (m08_axi_awqos),
    .s_axi_awregion (m08_axi_awregion),
    .s_axi_awvalid  (m08_axi_awvalid),
    .s_axi_awready  (m08_axi_awready),
    .s_axi_wdata    (m08_axi_wdata),
    .s_axi_wstrb    (m08_axi_wstrb),
    .s_axi_wlast    (m08_axi_wlast),
    .s_axi_wvalid   (m08_axi_wvalid),
    .s_axi_wready   (m08_axi_wready),
    .s_axi_bid      (m08_axi_bid),
    .s_axi_bresp    (m08_axi_bresp),
    .s_axi_bvalid   (m08_axi_bvalid),
    .s_axi_bready   (m08_axi_bready),
    .s_axi_arid     (m08_axi_arid),
    .s_axi_araddr   (m08_axi_araddr),
    .s_axi_arlen    (m08_axi_arlen),
    .s_axi_arsize   (m08_axi_arsize),
    .s_axi_arburst  (m08_axi_arburst),
    .s_axi_arlock   (m08_axi_arlock),
    .s_axi_arcache  (m08_axi_arcache),
    .s_axi_arprot   (m08_axi_arprot),
    .s_axi_arqos    (m08_axi_arqos),
    .s_axi_arregion (m08_axi_arregion),
    .s_axi_arvalid  (m08_axi_arvalid),
    .s_axi_arready  (m08_axi_arready),
    .s_axi_rid      (m08_axi_rid),
    .s_axi_rdata    (m08_axi_rdata),
    .s_axi_rresp    (m08_axi_rresp),
    .s_axi_rlast    (m08_axi_rlast),
    .s_axi_rvalid   (m08_axi_rvalid),
    .s_axi_rready   (m08_axi_rready),
    .timer_irq_a    (timer_irq_a),
    .timer_irq_b    (timer_irq_b)
);
// ---- M09: Reset Controller / WDT ----
reset_ctrl #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_reset_ctrl (
    .clk            (clk),
    .rst            (rst),
    .s_axi_awid     (m09_axi_awid),
    .s_axi_awaddr   (m09_axi_awaddr),
    .s_axi_awlen    (m09_axi_awlen),
    .s_axi_awsize   (m09_axi_awsize),
    .s_axi_awburst  (m09_axi_awburst),
    .s_axi_awlock   (m09_axi_awlock),
    .s_axi_awcache  (m09_axi_awcache),
    .s_axi_awprot   (m09_axi_awprot),
    .s_axi_awqos    (m09_axi_awqos),
    .s_axi_awregion (m09_axi_awregion),
    .s_axi_awvalid  (m09_axi_awvalid),
    .s_axi_awready  (m09_axi_awready),
    .s_axi_wdata    (m09_axi_wdata),
    .s_axi_wstrb    (m09_axi_wstrb),
    .s_axi_wlast    (m09_axi_wlast),
    .s_axi_wvalid   (m09_axi_wvalid),
    .s_axi_wready   (m09_axi_wready),
    .s_axi_bid      (m09_axi_bid),
    .s_axi_bresp    (m09_axi_bresp),
    .s_axi_bvalid   (m09_axi_bvalid),
    .s_axi_bready   (m09_axi_bready),
    .s_axi_arid     (m09_axi_arid),
    .s_axi_araddr   (m09_axi_araddr),
    .s_axi_arlen    (m09_axi_arlen),
    .s_axi_arsize   (m09_axi_arsize),
    .s_axi_arburst  (m09_axi_arburst),
    .s_axi_arlock   (m09_axi_arlock),
    .s_axi_arcache  (m09_axi_arcache),
    .s_axi_arprot   (m09_axi_arprot),
    .s_axi_arqos    (m09_axi_arqos),
    .s_axi_arregion (m09_axi_arregion),
    .s_axi_arvalid  (m09_axi_arvalid),
    .s_axi_arready  (m09_axi_arready),
    .s_axi_rid      (m09_axi_rid),
    .s_axi_rdata    (m09_axi_rdata),
    .s_axi_rresp    (m09_axi_rresp),
    .s_axi_rlast    (m09_axi_rlast),
    .s_axi_rvalid   (m09_axi_rvalid),
    .s_axi_rready   (m09_axi_rready),
    .por_reset      (por_rst_in),
    .sys_reset_req  (sys_reset_req),
    .wdt_irq        (wdt_irq)
);
// ---- M10: boot_rom ----
boot_rom #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .STRB_WIDTH (STRB_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    .ROM_DEPTH  (1024)
) u_boot_rom (
    .clk            (clk),
    .rst            (sys_reset_active),
    .s_axi_awid     (m10_axi_awid),
    .s_axi_awaddr   (m10_axi_awaddr),
    .s_axi_awlen    (m10_axi_awlen),
    .s_axi_awsize   (m10_axi_awsize),
    .s_axi_awburst  (m10_axi_awburst),
    .s_axi_awlock   (m10_axi_awlock),
    .s_axi_awcache  (m10_axi_awcache),
    .s_axi_awprot   (m10_axi_awprot),
    .s_axi_awqos    (m10_axi_awqos),
    .s_axi_awregion (m10_axi_awregion),
    .s_axi_awvalid  (m10_axi_awvalid),
    .s_axi_awready  (m10_axi_awready),
    .s_axi_wdata    (m10_axi_wdata),
    .s_axi_wstrb    (m10_axi_wstrb),
    .s_axi_wlast    (m10_axi_wlast),
    .s_axi_wvalid   (m10_axi_wvalid),
    .s_axi_wready   (m10_axi_wready),
    .s_axi_bid      (m10_axi_bid),
    .s_axi_bresp    (m10_axi_bresp),
    .s_axi_bvalid   (m10_axi_bvalid),
    .s_axi_bready   (m10_axi_bready),
    .s_axi_arid     (m10_axi_arid),
    .s_axi_araddr   (m10_axi_araddr),
    .s_axi_arlen    (m10_axi_arlen),
    .s_axi_arsize   (m10_axi_arsize),
    .s_axi_arburst  (m10_axi_arburst),
    .s_axi_arlock   (m10_axi_arlock),
    .s_axi_arcache  (m10_axi_arcache),
    .s_axi_arprot   (m10_axi_arprot),
    .s_axi_arqos    (m10_axi_arqos),
    .s_axi_arregion (m10_axi_arregion),
    .s_axi_arvalid  (m10_axi_arvalid),
    .s_axi_arready  (m10_axi_arready),
    .s_axi_rid      (m10_axi_rid),
    .s_axi_rdata    (m10_axi_rdata),
    .s_axi_rresp    (m10_axi_rresp),
    .s_axi_rlast    (m10_axi_rlast),
    .s_axi_rvalid   (m10_axi_rvalid),
    .s_axi_rready   (m10_axi_rready)

);
endmodule

`resetall
