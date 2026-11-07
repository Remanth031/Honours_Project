// =============================================================================
// core_types_pkg.sv – Core Direct Bus Types & Definitions
// =============================================================================
`ifndef CORE_TYPES_PKG_SV
`define CORE_TYPES_PKG_SV

package core_types_pkg;

    typedef enum bit {
        CORE_READ  = 1'b0,
        CORE_WRITE = 1'b1
    } core_op_e;

    typedef enum bit [1:0] {
        CORE_RESP_OKAY   = 2'b00,
        CORE_RESP_EXOKAY = 2'b01,
        CORE_RESP_SLVERR = 2'b10,
        CORE_RESP_DECERR = 2'b11
    } core_resp_e;

endpackage : core_types_pkg

`endif // CORE_TYPES_PKG_SV
