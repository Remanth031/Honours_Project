// =============================================================================
// axi_if.sv – AXI4 Interface Definition for UVM VIP
// =============================================================================
`ifndef AXI_IF_SV
`define AXI_IF_SV

interface axi_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH / 8,
    parameter ID_WIDTH   = 8
)(
    input logic clk,
    input logic rst_n
);

    // Write Address Channel (AW)
    logic [ID_WIDTH-1:0]    awid;
    logic [ADDR_WIDTH-1:0]  awaddr;
    logic [7:0]             awlen;
    logic [2:0]             awsize;
    logic [1:0]             awburst;
    logic                   awlock;
    logic [3:0]             awcache;
    logic [2:0]             awprot;
    logic [3:0]             awqos;
    logic                   awvalid;
    logic                   awready;

    // Write Data Channel (W)
    logic [DATA_WIDTH-1:0]  wdata;
    logic [STRB_WIDTH-1:0]  wstrb;
    logic                   wlast;
    logic                   wvalid;
    logic                   wready;

    // Write Response Channel (B)
    logic [ID_WIDTH-1:0]    bid;
    logic [1:0]             bresp;
    logic                   bvalid;
    logic                   bready;

    // Read Address Channel (AR)
    logic [ID_WIDTH-1:0]    arid;
    logic [ADDR_WIDTH-1:0]  araddr;
    logic [7:0]             arlen;
    logic [2:0]             arsize;
    logic [1:0]             arburst;
    logic                   arlock;
    logic [3:0]             arcache;
    logic [2:0]             arprot;
    logic [3:0]             arqos;
    logic                   arvalid;
    logic                   arready;

    // Read Data Channel (R)
    logic [ID_WIDTH-1:0]    rid;
    logic [DATA_WIDTH-1:0]  rdata;
    logic [1:0]             rresp;
    logic                   rlast;
    logic                   rvalid;
    logic                   rready;

    // Driver Clocking Block
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid;
        input  awready;

        output wdata, wstrb, wlast, wvalid;
        input  wready;

        input  bid, bresp, bvalid;
        output bready;

        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid;
        input  arready;

        input  rid, rdata, rresp, rlast, rvalid;
        output rready;
    endclocking

    // Monitor Clocking Block
    clocking mon_cb @(posedge clk);
        default input #1step output #1ns;
        input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking

    modport master (
        clocking drv_cb,
        input clk, rst_n
    );

    modport monitor (
        clocking mon_cb,
        input clk, rst_n
    );

endinterface : axi_if

`endif // AXI_IF_SV
