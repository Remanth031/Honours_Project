// =============================================================================
// core_if.sv – Core-to-UART Direct Read/Write Bus Interface
// =============================================================================
`ifndef CORE_IF_SV
`define CORE_IF_SV

interface core_if #(
    parameter ADDR_WIDTH = 5,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH / 8
)(
    input logic clk,
    input logic rst_n
);

    // Direct Write Channel
    logic [ADDR_WIDTH-1:0] awaddr;
    logic                  awvalid;
    logic                  awready;
    logic [DATA_WIDTH-1:0] wdata;
    logic [STRB_WIDTH-1:0] wstrb;
    logic                  wvalid;
    logic                  wready;
    logic [1:0]            bresp;
    logic                  bvalid;
    logic                  bready;

    // Direct Read Channel
    logic [ADDR_WIDTH-1:0] araddr;
    logic                  arvalid;
    logic                  arready;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rvalid;
    logic                  rready;

    // Driver Clocking Block
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output awaddr, awvalid, wdata, wstrb, wvalid, bready;
        input  awready, wready, bresp, bvalid;

        output araddr, arvalid, rready;
        input  arready, rdata, rresp, rvalid;
    endclocking

    // Monitor Clocking Block
    clocking mon_cb @(posedge clk);
        default input #1step output #1ns;
        input awaddr, awvalid, awready, wdata, wstrb, wvalid, wready, bresp, bvalid, bready;
        input araddr, arvalid, arready, rdata, rresp, rvalid, rready;
    endclocking

    modport master (
        clocking drv_cb,
        input clk, rst_n
    );

    modport monitor (
        clocking mon_cb,
        input clk, rst_n
    );

endinterface : core_if

`endif // CORE_IF_SV
