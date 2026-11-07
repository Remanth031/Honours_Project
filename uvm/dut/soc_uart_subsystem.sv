// =============================================================================
// soc_uart_subsystem.sv – Subsystem Integrating Core Interface, AXI Interconnect & UART
// =============================================================================
`timescale 1ns / 1ps
`default_nettype wire

module soc_uart_subsystem #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8
)(
    input  wire         clk,
    input  wire         rst_n,

    // Core / AXI Master 0 Interface (Connects to AXI VIP / CPU initiator)
    input  wire [ID_WIDTH-1:0]    s00_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s00_axi_awaddr,
    input  wire [7:0]             s00_axi_awlen,
    input  wire [2:0]             s00_axi_awsize,
    input  wire [1:0]             s00_axi_awburst,
    input  wire                   s00_axi_awlock,
    input  wire [3:0]             s00_axi_awcache,
    input  wire [2:0]             s00_axi_awprot,
    input  wire [3:0]             s00_axi_awqos,
    input  wire                   s00_axi_awvalid,
    output wire                   s00_axi_awready,

    input  wire [DATA_WIDTH-1:0]  s00_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s00_axi_wstrb,
    input  wire                   s00_axi_wlast,
    input  wire                   s00_axi_wvalid,
    output wire                   s00_axi_wready,

    output wire [ID_WIDTH-1:0]    s00_axi_bid,
    output wire [1:0]             s00_axi_bresp,
    output wire                   s00_axi_bvalid,
    input  wire                   s00_axi_bready,

    input  wire [ID_WIDTH-1:0]    s00_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s00_axi_araddr,
    input  wire [7:0]             s00_axi_arlen,
    input  wire [2:0]             s00_axi_arsize,
    input  wire [1:0]             s00_axi_arburst,
    input  wire                   s00_axi_arlock,
    input  wire [3:0]             s00_axi_arcache,
    input  wire [2:0]             s00_axi_arprot,
    input  wire [3:0]             s00_axi_arqos,
    input  wire                   s00_axi_arvalid,
    output wire                   s00_axi_arready,

    output wire [ID_WIDTH-1:0]    s00_axi_rid,
    output wire [DATA_WIDTH-1:0]  s00_axi_rdata,
    output wire [1:0]             s00_axi_rresp,
    output wire                   s00_axi_rlast,
    output wire                   s00_axi_rvalid,
    input  wire                   s00_axi_rready,

    // UART Serial External Pins
    input  wire                   uart_rx,
    output wire                   uart_tx,
    output wire                   uart_irq
);

    wire sys_reset = ~rst_n;

    // Address Map constants
    localparam [31:0] M00_BASE = 32'h0000_0000;
    localparam [31:0] M01_BASE = 32'h1000_0000;
    localparam [31:0] M02_BASE = 32'h2000_0000;
    localparam [31:0] M03_BASE = 32'h2001_0000;
    localparam [31:0] M04_BASE = 32'h2002_0000;
    localparam [31:0] M05_BASE = 32'h2003_0000; // UART IP
    localparam [31:0] M06_BASE = 32'h2004_0000;
    localparam [31:0] M07_BASE = 32'h2005_0000;
    localparam [31:0] M08_BASE = 32'h2006_0000;
    localparam [31:0] M09_BASE = 32'h2007_0000;
    localparam [31:0] M10_BASE = 32'h3000_0000;

    // Master port 05 (UART) interconnect signals
    wire [ID_WIDTH-1:0]   m05_axi_awid;
    wire [ADDR_WIDTH-1:0] m05_axi_awaddr;
    wire [7:0]            m05_axi_awlen;
    wire [2:0]            m05_axi_awsize;
    wire [1:0]            m05_axi_awburst;
    wire                  m05_axi_awlock;
    wire [3:0]            m05_axi_awcache;
    wire [2:0]            m05_axi_awprot;
    wire [3:0]            m05_axi_awqos;
    wire [3:0]            m05_axi_awregion;
    wire                  m05_axi_awvalid;
    wire                  m05_axi_awready;

    wire [DATA_WIDTH-1:0] m05_axi_wdata;
    wire [STRB_WIDTH-1:0] m05_axi_wstrb;
    wire                  m05_axi_wlast;
    wire                  m05_axi_wvalid;
    wire                  m05_axi_wready;

    wire [ID_WIDTH-1:0]   m05_axi_bid;
    wire [1:0]            m05_axi_bresp;
    wire                  m05_axi_bvalid;
    wire                  m05_axi_bready;

    wire [ID_WIDTH-1:0]   m05_axi_arid;
    wire [ADDR_WIDTH-1:0] m05_axi_araddr;
    wire [7:0]            m05_axi_arlen;
    wire [2:0]            m05_axi_arsize;
    wire [1:0]            m05_axi_arburst;
    wire                  m05_axi_arlock;
    wire [3:0]            m05_axi_arcache;
    wire [2:0]            m05_axi_arprot;
    wire [3:0]            m05_axi_arqos;
    wire [3:0]            m05_axi_arregion;
    wire                  m05_axi_arvalid;
    wire                  m05_axi_arready;

    wire [ID_WIDTH-1:0]   m05_axi_rid;
    wire [DATA_WIDTH-1:0] m05_axi_rdata;
    wire [1:0]            m05_axi_rresp;
    wire                  m05_axi_rlast;
    wire                  m05_axi_rvalid;
    wire                  m05_axi_rready;

    // Full 4x11 AXI Interconnect instantiation
    axi_interconnect_wrap_4x11 #(
        .DATA_WIDTH          (DATA_WIDTH),
        .ADDR_WIDTH          (ADDR_WIDTH),
        .STRB_WIDTH          (STRB_WIDTH),
        .ID_WIDTH            (ID_WIDTH),
        .AWUSER_ENABLE       (0),
        .WUSER_ENABLE        (0),
        .BUSER_ENABLE        (0),
        .ARUSER_ENABLE       (0),
        .RUSER_ENABLE        (0),
        .FORWARD_ID          (0),
        .M_REGIONS           (1),

        .M00_BASE_ADDR       (M00_BASE), .M00_ADDR_WIDTH ({1{32'd24}}), .M00_CONNECT_READ (4'b0001), .M00_CONNECT_WRITE (4'b0001),
        .M01_BASE_ADDR       (M01_BASE), .M01_ADDR_WIDTH ({1{32'd24}}), .M01_CONNECT_READ (4'b0001), .M01_CONNECT_WRITE (4'b0001),
        .M02_BASE_ADDR       (M02_BASE), .M02_ADDR_WIDTH ({1{32'd12}}), .M02_CONNECT_READ (4'b0001), .M02_CONNECT_WRITE (4'b0001),
        .M03_BASE_ADDR       (M03_BASE), .M03_ADDR_WIDTH ({1{32'd12}}), .M03_CONNECT_READ (4'b0001), .M03_CONNECT_WRITE (4'b0001),
        .M04_BASE_ADDR       (M04_BASE), .M04_ADDR_WIDTH ({1{32'd12}}), .M04_CONNECT_READ (4'b0001), .M04_CONNECT_WRITE (4'b0001),
        .M05_BASE_ADDR       (M05_BASE), .M05_ADDR_WIDTH ({1{32'd12}}), .M05_CONNECT_READ (4'b0001), .M05_CONNECT_WRITE (4'b0001), // UART
        .M06_BASE_ADDR       (M06_BASE), .M06_ADDR_WIDTH ({1{32'd12}}), .M06_CONNECT_READ (4'b0001), .M06_CONNECT_WRITE (4'b0001),
        .M07_BASE_ADDR       (M07_BASE), .M07_ADDR_WIDTH ({1{32'd12}}), .M07_CONNECT_READ (4'b0001), .M07_CONNECT_WRITE (4'b0001),
        .M08_BASE_ADDR       (M08_BASE), .M08_ADDR_WIDTH ({1{32'd12}}), .M08_CONNECT_READ (4'b0001), .M08_CONNECT_WRITE (4'b0001),
        .M09_BASE_ADDR       (M09_BASE), .M09_ADDR_WIDTH ({1{32'd12}}), .M09_CONNECT_READ (4'b0001), .M09_CONNECT_WRITE (4'b0001),
        .M10_BASE_ADDR       (M10_BASE), .M10_ADDR_WIDTH ({1{32'd12}}), .M10_CONNECT_READ (4'b0001), .M10_CONNECT_WRITE (4'b0001)
    ) u_interconnect (
        .clk                 (clk),
        .rst                 (sys_reset),

        // S00: Core Interface (Active Master from VIP)
        .s00_axi_awid        (s00_axi_awid),
        .s00_axi_awaddr      (s00_axi_awaddr),
        .s00_axi_awlen       (s00_axi_awlen),
        .s00_axi_awsize      (s00_axi_awsize),
        .s00_axi_awburst     (s00_axi_awburst),
        .s00_axi_awlock      (s00_axi_awlock),
        .s00_axi_awcache     (s00_axi_awcache),
        .s00_axi_awprot      (s00_axi_awprot),
        .s00_axi_awqos       (s00_axi_awqos),
        .s00_axi_awuser      (1'b0),
        .s00_axi_awvalid     (s00_axi_awvalid),
        .s00_axi_awready     (s00_axi_awready),
        .s00_axi_wdata       (s00_axi_wdata),
        .s00_axi_wstrb       (s00_axi_wstrb),
        .s00_axi_wlast       (s00_axi_wlast),
        .s00_axi_wuser       (1'b0),
        .s00_axi_wvalid      (s00_axi_wvalid),
        .s00_axi_wready      (s00_axi_wready),
        .s00_axi_bid         (s00_axi_bid),
        .s00_axi_bresp       (s00_axi_bresp),
        .s00_axi_buser       (),
        .s00_axi_bvalid      (s00_axi_bvalid),
        .s00_axi_bready      (s00_axi_bready),
        .s00_axi_arid        (s00_axi_arid),
        .s00_axi_araddr      (s00_axi_araddr),
        .s00_axi_arlen       (s00_axi_arlen),
        .s00_axi_arsize      (s00_axi_arsize),
        .s00_axi_arburst     (s00_axi_arburst),
        .s00_axi_arlock      (s00_axi_arlock),
        .s00_axi_arcache     (s00_axi_arcache),
        .s00_axi_arprot      (s00_axi_arprot),
        .s00_axi_arqos       (s00_axi_arqos),
        .s00_axi_aruser      (1'b0),
        .s00_axi_arvalid     (s00_axi_arvalid),
        .s00_axi_arready     (s00_axi_arready),
        .s00_axi_rid         (s00_axi_rid),
        .s00_axi_rdata       (s00_axi_rdata),
        .s00_axi_rresp       (s00_axi_rresp),
        .s00_axi_rlast       (s00_axi_rlast),
        .s00_axi_ruser       (),
        .s00_axi_rvalid      (s00_axi_rvalid),
        .s00_axi_rready      (s00_axi_rready),

        // S01-S03: Tied to Idle
        .s01_axi_awid('0), .s01_axi_awaddr('0), .s01_axi_awlen('0), .s01_axi_awsize('0), .s01_axi_awburst('0), .s01_axi_awlock('0), .s01_axi_awcache('0), .s01_axi_awprot('0), .s01_axi_awqos('0), .s01_axi_awuser('0), .s01_axi_awvalid('0), .s01_axi_awready(),
        .s01_axi_wdata('0), .s01_axi_wstrb('0), .s01_axi_wlast('0), .s01_axi_wuser('0), .s01_axi_wvalid('0), .s01_axi_wready(),
        .s01_axi_bid(), .s01_axi_bresp(), .s01_axi_buser(), .s01_axi_bvalid(), .s01_axi_bready('0),
        .s01_axi_arid('0), .s01_axi_araddr('0), .s01_axi_arlen('0), .s01_axi_arsize('0), .s01_axi_arburst('0), .s01_axi_arlock('0), .s01_axi_arcache('0), .s01_axi_arprot('0), .s01_axi_arqos('0), .s01_axi_aruser('0), .s01_axi_arvalid('0), .s01_axi_arready(),
        .s01_axi_rid(), .s01_axi_rdata(), .s01_axi_rresp(), .s01_axi_rlast(), .s01_axi_ruser(), .s01_axi_rvalid(), .s01_axi_rready('0),

        .s02_axi_awid('0), .s02_axi_awaddr('0), .s02_axi_awlen('0), .s02_axi_awsize('0), .s02_axi_awburst('0), .s02_axi_awlock('0), .s02_axi_awcache('0), .s02_axi_awprot('0), .s02_axi_awqos('0), .s02_axi_awuser('0), .s02_axi_awvalid('0), .s02_axi_awready(),
        .s02_axi_wdata('0), .s02_axi_wstrb('0), .s02_axi_wlast('0), .s02_axi_wuser('0), .s02_axi_wvalid('0), .s02_axi_wready(),
        .s02_axi_bid(), .s02_axi_bresp(), .s02_axi_buser(), .s02_axi_bvalid(), .s02_axi_bready('0),
        .s02_axi_arid('0), .s02_axi_araddr('0), .s02_axi_arlen('0), .s02_axi_arsize('0), .s02_axi_arburst('0), .s02_axi_arlock('0), .s02_axi_arcache('0), .s02_axi_arprot('0), .s02_axi_arqos('0), .s02_axi_aruser('0), .s02_axi_arvalid('0), .s02_axi_arready(),
        .s02_axi_rid(), .s02_axi_rdata(), .s02_axi_rresp(), .s02_axi_rlast(), .s02_axi_ruser(), .s02_axi_rvalid(), .s02_axi_rready('0),

        .s03_axi_awid('0), .s03_axi_awaddr('0), .s03_axi_awlen('0), .s03_axi_awsize('0), .s03_axi_awburst('0), .s03_axi_awlock('0), .s03_axi_awcache('0), .s03_axi_awprot('0), .s03_axi_awqos('0), .s03_axi_awuser('0), .s03_axi_awvalid('0), .s03_axi_awready(),
        .s03_axi_wdata('0), .s03_axi_wstrb('0), .s03_axi_wlast('0), .s03_axi_wuser('0), .s03_axi_wvalid('0), .s03_axi_wready(),
        .s03_axi_bid(), .s03_axi_bresp(), .s03_axi_buser(), .s03_axi_bvalid(), .s03_axi_bready('0),
        .s03_axi_arid('0), .s03_axi_araddr('0), .s03_axi_arlen('0), .s03_axi_arsize('0), .s03_axi_arburst('0), .s03_axi_arlock('0), .s03_axi_arcache('0), .s03_axi_arprot('0), .s03_axi_arqos('0), .s03_axi_aruser('0), .s03_axi_arvalid('0), .s03_axi_arready(),
        .s03_axi_rid(), .s03_axi_rdata(), .s03_axi_rresp(), .s03_axi_rlast(), .s03_axi_ruser(), .s03_axi_rvalid(), .s03_axi_rready('0),

        // M00..M04 Tied to Default Responders
        .m00_axi_awid(), .m00_axi_awaddr(), .m00_axi_awlen(), .m00_axi_awsize(), .m00_axi_awburst(), .m00_axi_awlock(), .m00_axi_awcache(), .m00_axi_awprot(), .m00_axi_awqos(), .m00_axi_awregion(), .m00_axi_awuser(), .m00_axi_awvalid(), .m00_axi_awready(1'b1),
        .m00_axi_wdata(), .m00_axi_wstrb(), .m00_axi_wlast(), .m00_axi_wuser(), .m00_axi_wvalid(), .m00_axi_wready(1'b1),
        .m00_axi_bid('0), .m00_axi_bresp(2'b00), .m00_axi_buser(1'b0), .m00_axi_bvalid(1'b0), .m00_axi_bready(),
        .m00_axi_arid(), .m00_axi_araddr(), .m00_axi_arlen(), .m00_axi_arsize(), .m00_axi_arburst(), .m00_axi_arlock(), .m00_axi_arcache(), .m00_axi_arprot(), .m00_axi_arqos(), .m00_axi_arregion(), .m00_axi_aruser(), .m00_axi_arvalid(), .m00_axi_arready(1'b1),
        .m00_axi_rid('0), .m00_axi_rdata('0), .m00_axi_rresp(2'b00), .m00_axi_rlast(1'b1), .m00_axi_ruser(1'b0), .m00_axi_rvalid(1'b0), .m00_axi_rready(),

        .m01_axi_awid(), .m01_axi_awaddr(), .m01_axi_awlen(), .m01_axi_awsize(), .m01_axi_awburst(), .m01_axi_awlock(), .m01_axi_awcache(), .m01_axi_awprot(), .m01_axi_awqos(), .m01_axi_awregion(), .m01_axi_awuser(), .m01_axi_awvalid(), .m01_axi_awready(1'b1),
        .m01_axi_wdata(), .m01_axi_wstrb(), .m01_axi_wlast(), .m01_axi_wuser(), .m01_axi_wvalid(), .m01_axi_wready(1'b1),
        .m01_axi_bid('0), .m01_axi_bresp(2'b00), .m01_axi_buser(1'b0), .m01_axi_bvalid(1'b0), .m01_axi_bready(),
        .m01_axi_arid(), .m01_axi_araddr(), .m01_axi_arlen(), .m01_axi_arsize(), .m01_axi_arburst(), .m01_axi_arlock(), .m01_axi_arcache(), .m01_axi_arprot(), .m01_axi_arqos(), .m01_axi_arregion(), .m01_axi_aruser(), .m01_axi_arvalid(), .m01_axi_arready(1'b1),
        .m01_axi_rid('0), .m01_axi_rdata('0), .m01_axi_rresp(2'b00), .m01_axi_rlast(1'b1), .m01_axi_ruser(1'b0), .m01_axi_rvalid(1'b0), .m01_axi_rready(),

        .m02_axi_awid(), .m02_axi_awaddr(), .m02_axi_awlen(), .m02_axi_awsize(), .m02_axi_awburst(), .m02_axi_awlock(), .m02_axi_awcache(), .m02_axi_awprot(), .m02_axi_awqos(), .m02_axi_awregion(), .m02_axi_awuser(), .m02_axi_awvalid(), .m02_axi_awready(1'b1),
        .m02_axi_wdata(), .m02_axi_wstrb(), .m02_axi_wlast(), .m02_axi_wuser(), .m02_axi_wvalid(), .m02_axi_wready(1'b1),
        .m02_axi_bid('0), .m02_axi_bresp(2'b00), .m02_axi_buser(1'b0), .m02_axi_bvalid(1'b0), .m02_axi_bready(),
        .m02_axi_arid(), .m02_axi_araddr(), .m02_axi_arlen(), .m02_axi_arsize(), .m02_axi_arburst(), .m02_axi_arlock(), .m02_axi_arcache(), .m02_axi_arprot(), .m02_axi_arqos(), .m02_axi_arregion(), .m02_axi_aruser(), .m02_axi_arvalid(), .m02_axi_arready(1'b1),
        .m02_axi_rid('0), .m02_axi_rdata('0), .m02_axi_rresp(2'b00), .m02_axi_rlast(1'b1), .m02_axi_ruser(1'b0), .m02_axi_rvalid(1'b0), .m02_axi_rready(),

        .m03_axi_awid(), .m03_axi_awaddr(), .m03_axi_awlen(), .m03_axi_awsize(), .m03_axi_awburst(), .m03_axi_awlock(), .m03_axi_awcache(), .m03_axi_awprot(), .m03_axi_awqos(), .m03_axi_awregion(), .m03_axi_awuser(), .m03_axi_awvalid(), .m03_axi_awready(1'b1),
        .m03_axi_wdata(), .m03_axi_wstrb(), .m03_axi_wlast(), .m03_axi_wuser(), .m03_axi_wvalid(), .m03_axi_wready(1'b1),
        .m03_axi_bid('0), .m03_axi_bresp(2'b00), .m03_axi_buser(1'b0), .m03_axi_bvalid(1'b0), .m03_axi_bready(),
        .m03_axi_arid(), .m03_axi_araddr(), .m03_axi_arlen(), .m03_axi_arsize(), .m03_axi_arburst(), .m03_axi_arlock(), .m03_axi_arcache(), .m03_axi_arprot(), .m03_axi_arqos(), .m03_axi_arregion(), .m03_axi_aruser(), .m03_axi_arvalid(), .m03_axi_arready(1'b1),
        .m03_axi_rid('0), .m03_axi_rdata('0), .m03_axi_rresp(2'b00), .m03_axi_rlast(1'b1), .m03_axi_ruser(1'b0), .m03_axi_rvalid(1'b0), .m03_axi_rready(),

        .m04_axi_awid(), .m04_axi_awaddr(), .m04_axi_awlen(), .m04_axi_awsize(), .m04_axi_awburst(), .m04_axi_awlock(), .m04_axi_awcache(), .m04_axi_awprot(), .m04_axi_awqos(), .m04_axi_awregion(), .m04_axi_awuser(), .m04_axi_awvalid(), .m04_axi_awready(1'b1),
        .m04_axi_wdata(), .m04_axi_wstrb(), .m04_axi_wlast(), .m04_axi_wuser(), .m04_axi_wvalid(), .m04_axi_wready(1'b1),
        .m04_axi_bid('0), .m04_axi_bresp(2'b00), .m04_axi_buser(1'b0), .m04_axi_bvalid(1'b0), .m04_axi_bready(),
        .m04_axi_arid(), .m04_axi_araddr(), .m04_axi_arlen(), .m04_axi_arsize(), .m04_axi_arburst(), .m04_axi_arlock(), .m04_axi_arcache(), .m04_axi_arprot(), .m04_axi_arqos(), .m04_axi_arregion(), .m04_axi_aruser(), .m04_axi_arvalid(), .m04_axi_arready(1'b1),
        .m04_axi_rid('0), .m04_axi_rdata('0), .m04_axi_rresp(2'b00), .m04_axi_rlast(1'b1), .m04_axi_ruser(1'b0), .m04_axi_rvalid(1'b0), .m04_axi_rready(),

        // M05: Connected to UART IP!
        .m05_axi_awid        (m05_axi_awid),
        .m05_axi_awaddr      (m05_axi_awaddr),
        .m05_axi_awlen       (m05_axi_awlen),
        .m05_axi_awsize      (m05_axi_awsize),
        .m05_axi_awburst     (m05_axi_awburst),
        .m05_axi_awlock      (m05_axi_awlock),
        .m05_axi_awcache     (m05_axi_awcache),
        .m05_axi_awprot      (m05_axi_awprot),
        .m05_axi_awqos       (m05_axi_awqos),
        .m05_axi_awregion    (m05_axi_awregion),
        .m05_axi_awuser      (),
        .m05_axi_awvalid     (m05_axi_awvalid),
        .m05_axi_awready     (m05_axi_awready),
        .m05_axi_wdata       (m05_axi_wdata),
        .m05_axi_wstrb       (m05_axi_wstrb),
        .m05_axi_wlast       (m05_axi_wlast),
        .m05_axi_wuser       (),
        .m05_axi_wvalid      (m05_axi_wvalid),
        .m05_axi_wready      (m05_axi_wready),
        .m05_axi_bid         (m05_axi_bid),
        .m05_axi_bresp       (m05_axi_bresp),
        .m05_axi_buser       (1'b0),
        .m05_axi_bvalid      (m05_axi_bvalid),
        .m05_axi_bready      (m05_axi_bready),
        .m05_axi_arid        (m05_axi_arid),
        .m05_axi_araddr      (m05_axi_araddr),
        .m05_axi_arlen       (m05_axi_arlen),
        .m05_axi_arsize      (m05_axi_arsize),
        .m05_axi_arburst     (m05_axi_arburst),
        .m05_axi_arlock      (m05_axi_arlock),
        .m05_axi_arcache     (m05_axi_arcache),
        .m05_axi_arprot      (m05_axi_arprot),
        .m05_axi_arqos       (m05_axi_arqos),
        .m05_axi_arregion    (m05_axi_arregion),
        .m05_axi_aruser      (),
        .m05_axi_arvalid     (m05_axi_arvalid),
        .m05_axi_arready     (m05_axi_arready),
        .m05_axi_rid         (m05_axi_rid),
        .m05_axi_rdata       (m05_axi_rdata),
        .m05_axi_rresp       (m05_axi_rresp),
        .m05_axi_rlast       (m05_axi_rlast),
        .m05_axi_ruser       (1'b0),
        .m05_axi_rvalid      (m05_axi_rvalid),
        .m05_axi_rready      (m05_axi_rready),

        // M06..M10 Tied to Default Responders
        .m06_axi_awid(), .m06_axi_awaddr(), .m06_axi_awlen(), .m06_axi_awsize(), .m06_axi_awburst(), .m06_axi_awlock(), .m06_axi_awcache(), .m06_axi_awprot(), .m06_axi_awqos(), .m06_axi_awregion(), .m06_axi_awuser(), .m06_axi_awvalid(), .m06_axi_awready(1'b1),
        .m06_axi_wdata(), .m06_axi_wstrb(), .m06_axi_wlast(), .m06_axi_wuser(), .m06_axi_wvalid(), .m06_axi_wready(1'b1),
        .m06_axi_bid('0), .m06_axi_bresp(2'b00), .m06_axi_buser(1'b0), .m06_axi_bvalid(1'b0), .m06_axi_bready(),
        .m06_axi_arid(), .m06_axi_araddr(), .m06_axi_arlen(), .m06_axi_arsize(), .m06_axi_arburst(), .m06_axi_arlock(), .m06_axi_arcache(), .m06_axi_arprot(), .m06_axi_arqos(), .m06_axi_arregion(), .m06_axi_aruser(), .m06_axi_arvalid(), .m06_axi_arready(1'b1),
        .m06_axi_rid('0), .m06_axi_rdata('0), .m06_axi_rresp(2'b00), .m06_axi_rlast(1'b1), .m06_axi_ruser(1'b0), .m06_axi_rvalid(1'b0), .m06_axi_rready(),

        .m07_axi_awid(), .m07_axi_awaddr(), .m07_axi_awlen(), .m07_axi_awsize(), .m07_axi_awburst(), .m07_axi_awlock(), .m07_axi_awcache(), .m07_axi_awprot(), .m07_axi_awqos(), .m07_axi_awregion(), .m07_axi_awuser(), .m07_axi_awvalid(), .m07_axi_awready(1'b1),
        .m07_axi_wdata(), .m07_axi_wstrb(), .m07_axi_wlast(), .m07_axi_wuser(), .m07_axi_wvalid(), .m07_axi_wready(1'b1),
        .m07_axi_bid('0), .m07_axi_bresp(2'b00), .m07_axi_buser(1'b0), .m07_axi_bvalid(1'b0), .m07_axi_bready(),
        .m07_axi_arid(), .m07_axi_araddr(), .m07_axi_arlen(), .m07_axi_arsize(), .m07_axi_arburst(), .m07_axi_arlock(), .m07_axi_arcache(), .m07_axi_arprot(), .m07_axi_arqos(), .m07_axi_arregion(), .m07_axi_aruser(), .m07_axi_arvalid(), .m07_axi_arready(1'b1),
        .m07_axi_rid('0), .m07_axi_rdata('0), .m07_axi_rresp(2'b00), .m07_axi_rlast(1'b1), .m07_axi_ruser(1'b0), .m07_axi_rvalid(1'b0), .m07_axi_rready(),

        .m08_axi_awid(), .m08_axi_awaddr(), .m08_axi_awlen(), .m08_axi_awsize(), .m08_axi_awburst(), .m08_axi_awlock(), .m08_axi_awcache(), .m08_axi_awprot(), .m08_axi_awqos(), .m08_axi_awregion(), .m08_axi_awuser(), .m08_axi_awvalid(), .m08_axi_awready(1'b1),
        .m08_axi_wdata(), .m08_axi_wstrb(), .m08_axi_wlast(), .m08_axi_wuser(), .m08_axi_wvalid(), .m08_axi_wready(1'b1),
        .m08_axi_bid('0), .m08_axi_bresp(2'b00), .m08_axi_buser(1'b0), .m08_axi_bvalid(1'b0), .m08_axi_bready(),
        .m08_axi_arid(), .m08_axi_araddr(), .m08_axi_arlen(), .m08_axi_arsize(), .m08_axi_arburst(), .m08_axi_arlock(), .m08_axi_arcache(), .m08_axi_arprot(), .m08_axi_arqos(), .m08_axi_arregion(), .m08_axi_aruser(), .m08_axi_arvalid(), .m08_axi_arready(1'b1),
        .m08_axi_rid('0), .m08_axi_rdata('0), .m08_axi_rresp(2'b00), .m08_axi_rlast(1'b1), .m08_axi_ruser(1'b0), .m08_axi_rvalid(1'b0), .m08_axi_rready(),

        .m09_axi_awid(), .m09_axi_awaddr(), .m09_axi_awlen(), .m09_axi_awsize(), .m09_axi_awburst(), .m09_axi_awlock(), .m09_axi_awcache(), .m09_axi_awprot(), .m09_axi_awqos(), .m09_axi_awregion(), .m09_axi_awuser(), .m09_axi_awvalid(), .m09_axi_awready(1'b1),
        .m09_axi_wdata(), .m09_axi_wstrb(), .m09_axi_wlast(), .m09_axi_wuser(), .m09_axi_wvalid(), .m09_axi_wready(1'b1),
        .m09_axi_bid('0), .m09_axi_bresp(2'b00), .m09_axi_buser(1'b0), .m09_axi_bvalid(1'b0), .m09_axi_bready(),
        .m09_axi_arid(), .m09_axi_araddr(), .m09_axi_arlen(), .m09_axi_arsize(), .m09_axi_arburst(), .m09_axi_arlock(), .m09_axi_arcache(), .m09_axi_arprot(), .m09_axi_arqos(), .m09_axi_arregion(), .m09_axi_aruser(), .m09_axi_arvalid(), .m09_axi_arready(1'b1),
        .m09_axi_rid('0), .m09_axi_rdata('0), .m09_axi_rresp(2'b00), .m09_axi_rlast(1'b1), .m09_axi_ruser(1'b0), .m09_axi_rvalid(1'b0), .m09_axi_rready(),

        .m10_axi_awid(), .m10_axi_awaddr(), .m10_axi_awlen(), .m10_axi_awsize(), .m10_axi_awburst(), .m10_axi_awlock(), .m10_axi_awcache(), .m10_axi_awprot(), .m10_axi_awqos(), .m10_axi_awregion(), .m10_axi_awuser(), .m10_axi_awvalid(), .m10_axi_awready(1'b1),
        .m10_axi_wdata(), .m10_axi_wstrb(), .m10_axi_wlast(), .m10_axi_wuser(), .m10_axi_wvalid(), .m10_axi_wready(1'b1),
        .m10_axi_bid('0), .m10_axi_bresp(2'b00), .m10_axi_buser(1'b0), .m10_axi_bvalid(1'b0), .m10_axi_bready(),
        .m10_axi_arid(), .m10_axi_araddr(), .m10_axi_arlen(), .m10_axi_arsize(), .m10_axi_arburst(), .m10_axi_arlock(), .m10_axi_arcache(), .m10_axi_arprot(), .m10_axi_arqos(), .m10_axi_arregion(), .m10_axi_aruser(), .m10_axi_arvalid(), .m10_axi_arready(1'b1),
        .m10_axi_rid('0), .m10_axi_rdata('0), .m10_axi_rresp(2'b00), .m10_axi_rlast(1'b1), .m10_axi_ruser(1'b0), .m10_axi_rvalid(1'b0), .m10_axi_rready()
    );

    // M05: AXI-Lite UART IP instantiation
    wire [11:0] uart_bid_full;
    wire [11:0] uart_rid_full;

    axi_uart_top u_uart (
        .fixed_clk_i     (clk),
        .axi_aclk_i      (clk),
        .axi_aresetn_i   (rst_n),

        .axi_awid_i      ({{(12-ID_WIDTH){1'b0}}, m05_axi_awid}),
        .axi_awaddr_i    (m05_axi_awaddr[4:0]),
        .axi_awvalid_i   (m05_axi_awvalid),
        .axi_awready_o   (m05_axi_awready),

        .axi_wdata_i     (m05_axi_wdata),
        .axi_wstrb_i     (m05_axi_wstrb),
        .axi_wvalid_i    (m05_axi_wvalid),
        .axi_wready_o    (m05_axi_wready),

        .axi_bid_o       (uart_bid_full),
        .axi_bresp_o     (m05_axi_bresp),
        .axi_bvalid_o    (m05_axi_bvalid),
        .axi_bready_i    (m05_axi_bready),

        .axi_arid_i      ({{(12-ID_WIDTH){1'b0}}, m05_axi_arid}),
        .axi_araddr_i    (m05_axi_araddr[4:0]),
        .axi_arvalid_i   (m05_axi_arvalid),
        .axi_arready_o   (m05_axi_arready),

        .axi_rid_o       (uart_rid_full),
        .axi_rdata_o     (m05_axi_rdata),
        .axi_rresp_o     (m05_axi_rresp),
        .axi_rvalid_o    (m05_axi_rvalid),
        .axi_rready_i    (m05_axi_rready),

        .read_interrupt_o(uart_irq),
        .uart_tx_o       (uart_tx),
        .uart_rx_i       (uart_rx)
    );

    assign m05_axi_bid   = uart_bid_full[ID_WIDTH-1:0];
    assign m05_axi_rid   = uart_rid_full[ID_WIDTH-1:0];
    assign m05_axi_rlast = 1'b1;

endmodule

`default_nettype wire
