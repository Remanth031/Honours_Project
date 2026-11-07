// =============================================================================
// axi_types_pkg.sv – AXI4 Protocol Types & Definitions
// =============================================================================
`ifndef AXI_TYPES_PKG_SV
`define AXI_TYPES_PKG_SV

package axi_types_pkg;

    typedef enum bit {
        AXI_READ  = 1'b0,
        AXI_WRITE = 1'b1
    } axi_rw_e;

    typedef enum bit [1:0] {
        AXI_RESP_OKAY   = 2'b00,
        AXI_RESP_EXOKAY = 2'b01,
        AXI_RESP_SLVERR = 2'b10,
        AXI_RESP_DECERR = 2'b11
    } axi_resp_e;

    typedef enum bit [1:0] {
        AXI_BURST_FIXED = 2'b00,
        AXI_BURST_INCR  = 2'b01,
        AXI_BURST_WRAP  = 2'b10,
        AXI_BURST_RSVD  = 2'b11
    } axi_burst_e;

    typedef enum bit [2:0] {
        AXI_SIZE_1_BYTE   = 3'b000,
        AXI_SIZE_2_BYTES  = 3'b001,
        AXI_SIZE_4_BYTES  = 3'b010,
        AXI_SIZE_8_BYTES  = 3'b011,
        AXI_SIZE_16_BYTES = 3'b100,
        AXI_SIZE_32_BYTES = 3'b101,
        AXI_SIZE_64_BYTES = 3'b110,
        AXI_SIZE_128_BYTES= 3'b111
    } axi_size_e;

endpackage : axi_types_pkg

`endif // AXI_TYPES_PKG_SV
