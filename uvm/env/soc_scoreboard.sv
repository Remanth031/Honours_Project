// =============================================================================
// soc_scoreboard.sv – End-to-End Subsystem Scoreboard
// =============================================================================
`ifndef SOC_SCOREBOARD_SV
`define SOC_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_types_pkg::*;
import uart_types_pkg::*;
import axi_vip_pkg::*;
import uart_vip_pkg::*;

`uvm_analysis_imp_decl(_axi)
`uvm_analysis_imp_decl(_uart)

class soc_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(soc_scoreboard)

    uvm_analysis_imp_axi  #(axi_seq_item, soc_scoreboard) axi_export;
    uvm_analysis_imp_uart #(uart_seq_item, soc_scoreboard) uart_export;

    // Expected queues
    bit [7:0] expected_tx_q[$];
    bit [7:0] expected_rx_q[$];

    // Shadow registers for UART register verification
    bit [31:0] shadow_lcr;
    bit [31:0] shadow_ier;
    bit [31:0] shadow_baud;
    bit        dlab_active;

    // Statistics counters
    int unsigned num_axi_writes;
    int unsigned num_axi_reads;
    int unsigned num_reg_checks_passed;
    int unsigned num_reg_checks_failed;
    int unsigned num_tx_matches;
    int unsigned num_tx_mismatches;
    int unsigned num_rx_matches;
    int unsigned num_rx_mismatches;

    function new(string name = "soc_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        axi_export  = new("axi_export", this);
        uart_export = new("uart_export", this);

        shadow_lcr  = '0;
        shadow_ier  = '0;
        shadow_baud = 16;
        dlab_active = 0;

        num_axi_writes = 0;
        num_axi_reads  = 0;
        num_reg_checks_passed = 0;
        num_reg_checks_failed = 0;
        num_tx_matches    = 0;
        num_tx_mismatches = 0;
        num_rx_matches    = 0;
        num_rx_mismatches = 0;
    endfunction

    // ---- AXI Monitor Transactions ----
    virtual function void write_axi(axi_seq_item item);
        bit [31:0] reg_offset;
        reg_offset = item.addr & 32'h0000_00FF; // lower byte offset

        // Check AXI OKAY response
        if (item.resp[0] != AXI_RESP_OKAY) begin
            `uvm_error("SCB_AXI_RESP", $sformatf("AXI transaction returned error response: %s (addr=0x%08h)",
                                                 item.resp[0].name(), item.addr))
        end

        if (item.rw == AXI_WRITE) begin
            num_axi_writes++;
            `uvm_info("SCB_AXI_WR", $sformatf("AXI Write: Addr=0x%08h Data=0x%08h", item.addr, item.data[0]), UVM_HIGH)

            case (reg_offset)
                8'h00: begin // THR (Transmitter Holding Register)
                    if (!dlab_active) begin
                        bit [7:0] tx_byte = item.data[0][7:0];
                        expected_tx_q.push_back(tx_byte);
                        `uvm_info("SCB_TX_EXP", $sformatf("Queued expected TX byte from AXI write: 0x%02h ('%c')",
                                                          tx_byte, (tx_byte >= 32 && tx_byte <= 126) ? tx_byte : "."), UVM_MEDIUM)
                    end
                end
                8'h04: begin // IER
                    shadow_ier = item.data[0];
                end
                8'h08: begin // BAUD (when DLAB=1)
                    if (dlab_active) begin
                        shadow_baud = item.data[0];
                    end
                end
                8'h0C: begin // LCR
                    shadow_lcr = item.data[0];
                    dlab_active = shadow_lcr[7]; // DLAB is bit 7
                end
                default: ;
            endcase

        end else begin // AXI_READ
            num_axi_reads++;
            `uvm_info("SCB_AXI_RD", $sformatf("AXI Read: Addr=0x%08h Data=0x%08h", item.addr, item.data[0]), UVM_HIGH)

            case (reg_offset)
                8'h00: begin // RBR (Receiver Buffer Register)
                    if (!dlab_active) begin
                        if (expected_rx_q.size() > 0) begin
                            bit [7:0] exp_byte = expected_rx_q.pop_front();
                            bit [7:0] act_byte = item.data[0][7:0];
                            if (act_byte === exp_byte) begin
                                num_rx_matches++;
                                `uvm_info("SCB_RX_PASS", $sformatf("[MATCH] AXI read RBR matched sent byte: 0x%02h ('%c')",
                                                                   act_byte, (act_byte >= 32 && act_byte <= 126) ? act_byte : "."), UVM_LOW)
                            end else begin
                                num_rx_mismatches++;
                                `uvm_error("SCB_RX_FAIL", $sformatf("[MISMATCH] AXI read RBR expected=0x%02h got=0x%02h",
                                                                    exp_byte, act_byte))
                            end
                        end
                    end
                end
                8'h14: begin // LSR (Line Status Register)
                    `uvm_info("SCB_LSR", $sformatf("LSR status read: THRE=%b DR=%b", item.data[0][5], item.data[0][0]), UVM_HIGH)
                end
                default: ;
            endcase
        end
    endfunction

    // ---- UART Monitor Transactions ----
    virtual function void write_uart(uart_seq_item item);
        if (expected_tx_q.size() > 0) begin
            bit [7:0] exp_byte = expected_tx_q.pop_front();
            bit [7:0] act_byte = item.payload;

            if (act_byte === exp_byte) begin
                num_tx_matches++;
                `uvm_info("SCB_TX_PASS", $sformatf("[MATCH] Serial TX captured byte matched AXI written: 0x%02h ('%c')",
                                                   act_byte, (act_byte >= 32 && act_byte <= 126) ? act_byte : "."), UVM_LOW)
            end else begin
                num_tx_mismatches++;
                `uvm_error("SCB_TX_FAIL", $sformatf("[MISMATCH] Serial TX expected=0x%02h got=0x%02h",
                                                    exp_byte, act_byte))
            end
        end else begin
            `uvm_warning("SCB_UNEXP_TX", $sformatf("Unexpected serial TX byte received: 0x%02h", item.payload))
        end
    endfunction

    // External hook for sequences to push expected serial RX byte into scoreboard
    function void expect_rx_byte(bit [7:0] b);
        expected_rx_q.push_back(b);
        `uvm_info("SCB_RX_EXP", $sformatf("Queued expected RX byte: 0x%02h ('%c')",
                                          b, (b >= 32 && b <= 126) ? b : "."), UVM_MEDIUM)
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCB_REPORT", "================================================================================", UVM_NONE)
        `uvm_info("SCB_REPORT", "               SUBSYSTEM UVM SCOREBOARD VERIFICATION REPORT                     ", UVM_NONE)
        `uvm_info("SCB_REPORT", "================================================================================", UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  TOTAL AXI READ/WRITE TRANSACTIONS : %0d (Writes: %0d, Reads: %0d)",
                                         (num_axi_writes + num_axi_reads), num_axi_writes, num_axi_reads), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  UART TX MATCHES (AXI -> Serial)   : %0d / %0d",
                                         num_tx_matches, (num_tx_matches + num_tx_mismatches)), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  UART RX MATCHES (Serial -> AXI)   : %0d / %0d",
                                         num_rx_matches, (num_rx_matches + num_rx_mismatches)), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  TX MISMATCHES                     : %0d", num_tx_mismatches), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  RX MISMATCHES                     : %0d", num_rx_mismatches), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  REMAINING EXPECTED TX QUEUE       : %0d", expected_tx_q.size()), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  REMAINING EXPECTED RX QUEUE       : %0d", expected_rx_q.size()), UVM_NONE)
        `uvm_info("SCB_REPORT", "--------------------------------------------------------------------------------", UVM_NONE)

        if ((num_tx_mismatches == 0) && (num_rx_mismatches == 0) &&
            (expected_tx_q.size() == 0) && (expected_rx_q.size() == 0)) begin
            `uvm_info("SCB_REPORT", "  FINAL VERIFICATION STATUS         : *** ALL CHECKS PASSED PERFECTLY! ***", UVM_NONE)
        end else begin
            `uvm_error("SCB_REPORT", "  FINAL VERIFICATION STATUS         : *** VERIFICATION FAILED ***")
        end
        `uvm_info("SCB_REPORT", "================================================================================", UVM_NONE)
    endfunction

endclass : soc_scoreboard

`endif // SOC_SCOREBOARD_SV
