// =============================================================================
// core_uart_scoreboard.sv – Direct Core-to-UART UVM Scoreboard
// =============================================================================
`ifndef CORE_UART_SCOREBOARD_SV
`define CORE_UART_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import core_types_pkg::*;
import uart_types_pkg::*;
import core_vip_pkg::*;
import uart_vip_pkg::*;

`uvm_analysis_imp_decl(_core)
`uvm_analysis_imp_decl(_uart)

class core_uart_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(core_uart_scoreboard)

    uvm_analysis_imp_core #(core_seq_item, core_uart_scoreboard) core_export;
    uvm_analysis_imp_uart #(uart_seq_item, core_uart_scoreboard) uart_export;

    // Expected byte queues
    bit [7:0] expected_tx_q[$];
    bit [7:0] expected_rx_q[$];

    // Shadow state
    bit [31:0] shadow_lcr;
    bit [31:0] shadow_ier;
    bit [31:0] shadow_baud;
    bit        dlab_active;

    // Statistics
    int unsigned num_core_writes;
    int unsigned num_core_reads;
    int unsigned num_tx_matches;
    int unsigned num_tx_mismatches;
    int unsigned num_rx_matches;
    int unsigned num_rx_mismatches;

    function new(string name = "core_uart_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        core_export = new("core_export", this);
        uart_export = new("uart_export", this);

        shadow_lcr  = '0;
        shadow_ier  = '0;
        shadow_baud = 16;
        dlab_active = 0;

        num_core_writes   = 0;
        num_core_reads    = 0;
        num_tx_matches    = 0;
        num_tx_mismatches = 0;
        num_rx_matches    = 0;
        num_rx_mismatches = 0;
    endfunction

    // ---- Core Monitor Callback ----
    virtual function void write_core(core_seq_item item);
        if (item.resp != CORE_RESP_OKAY) begin
            `uvm_error("SCB_CORE_RESP", $sformatf("Direct transaction error response: %s (addr=0x%02h)",
                                                  item.resp.name(), item.addr))
        end

        if (item.op == CORE_WRITE) begin
            num_core_writes++;
            `uvm_info("SCB_CORE_WR", $sformatf("Direct Core Write: Addr=0x%02h Data=0x%08h", item.addr, item.data), UVM_HIGH)

            case (item.addr)
                5'h00: begin // THR
                    if (!dlab_active) begin
                        bit [7:0] tx_byte = item.data[7:0];
                        expected_tx_q.push_back(tx_byte);
                        `uvm_info("SCB_TX_EXP", $sformatf("Queued expected TX byte from Core write: 0x%02h ('%c')",
                                                          tx_byte, (tx_byte >= 32 && tx_byte <= 126) ? tx_byte : "."), UVM_MEDIUM)
                    end
                end
                5'h04: shadow_ier = item.data;
                5'h08: if (dlab_active) shadow_baud = item.data;
                5'h0C: begin
                    shadow_lcr  = item.data;
                    dlab_active = shadow_lcr[7]; // bit 7 = DLAB
                end
                default: ;
            endcase

        end else begin // CORE_READ
            num_core_reads++;
            `uvm_info("SCB_CORE_RD", $sformatf("Direct Core Read: Addr=0x%02h Data=0x%08h", item.addr, item.data), UVM_HIGH)

            case (item.addr)
                5'h00: begin // RBR
                    if (!dlab_active) begin
                        if (expected_rx_q.size() > 0) begin
                            bit [7:0] exp_byte = expected_rx_q.pop_front();
                            bit [7:0] act_byte = item.data[7:0];
                            if (act_byte === exp_byte) begin
                                num_rx_matches++;
                                `uvm_info("SCB_RX_PASS", $sformatf("[MATCH] Core read RBR matched sent byte: 0x%02h ('%c')",
                                                                   act_byte, (act_byte >= 32 && act_byte <= 126) ? act_byte : "."), UVM_LOW)
                            end else begin
                                num_rx_mismatches++;
                                `uvm_error("SCB_RX_FAIL", $sformatf("[MISMATCH] Core read RBR expected=0x%02h got=0x%02h",
                                                                    exp_byte, act_byte))
                            end
                        end
                    end
                end
                5'h14: begin // LSR
                    `uvm_info("SCB_LSR", $sformatf("Core read LSR: THRE=%b DR=%b", item.data[5], item.data[0]), UVM_HIGH)
                end
                default: ;
            endcase
        end
    endfunction

    // ---- UART Monitor Callback ----
    virtual function void write_uart(uart_seq_item item);
        if (expected_tx_q.size() > 0) begin
            bit [7:0] exp_byte = expected_tx_q.pop_front();
            bit [7:0] act_byte = item.payload;

            if (act_byte === exp_byte) begin
                num_tx_matches++;
                `uvm_info("SCB_TX_PASS", $sformatf("[MATCH] Serial TX captured byte matched Core written byte: 0x%02h ('%c')",
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

    function void expect_rx_byte(bit [7:0] b);
        expected_rx_q.push_back(b);
        `uvm_info("SCB_RX_EXP", $sformatf("Queued expected RX byte: 0x%02h ('%c')",
                                          b, (b >= 32 && b <= 126) ? b : "."), UVM_MEDIUM)
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCB_REPORT", "================================================================================", UVM_NONE)
        `uvm_info("SCB_REPORT", "         DIRECT CORE-TO-UART UVM SCOREBOARD VERIFICATION REPORT                 ", UVM_NONE)
        `uvm_info("SCB_REPORT", "================================================================================", UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  TOTAL CORE DIRECT READ/WRITE TRANSACTIONS : %0d (Writes: %0d, Reads: %0d)",
                                         (num_core_writes + num_core_reads), num_core_writes, num_core_reads), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  UART TX MATCHES (Core Write -> Serial)    : %0d / %0d",
                                         num_tx_matches, (num_tx_matches + num_tx_mismatches)), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  UART RX MATCHES (Serial -> Core Read)     : %0d / %0d",
                                         num_rx_matches, (num_rx_matches + num_rx_mismatches)), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  TX MISMATCHES                             : %0d", num_tx_mismatches), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  RX MISMATCHES                             : %0d", num_rx_mismatches), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  REMAINING EXPECTED TX QUEUE               : %0d", expected_tx_q.size()), UVM_NONE)
        `uvm_info("SCB_REPORT", $sformatf("  REMAINING EXPECTED RX QUEUE               : %0d", expected_rx_q.size()), UVM_NONE)
        `uvm_info("SCB_REPORT", "--------------------------------------------------------------------------------", UVM_NONE)

        if ((num_tx_mismatches == 0) && (num_rx_mismatches == 0) &&
            (expected_tx_q.size() == 0) && (expected_rx_q.size() == 0)) begin
            `uvm_info("SCB_REPORT", "  FINAL VERIFICATION STATUS                 : *** ALL CHECKS PASSED PERFECTLY! ***", UVM_NONE)
        end else begin
            `uvm_error("SCB_REPORT", "  FINAL VERIFICATION STATUS                 : *** VERIFICATION FAILED ***")
        end
        `uvm_info("SCB_REPORT", "================================================================================", UVM_NONE)
    endfunction

endclass : core_uart_scoreboard

`endif // CORE_UART_SCOREBOARD_SV
