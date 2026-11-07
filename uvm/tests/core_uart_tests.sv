// =============================================================================
// core_uart_tests.sv – Direct Core-to-UART UVM Testcases
// =============================================================================
`ifndef CORE_UART_TESTS_SV
`define CORE_UART_TESTS_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import core_types_pkg::*;
import uart_types_pkg::*;
import core_vip_pkg::*;
import uart_vip_pkg::*;
import core_uart_env_pkg::*;
`include "core_uart_sequences.sv"

// -----------------------------------------------------------------------------
// Base Test
// -----------------------------------------------------------------------------
class core_uart_base_test extends uvm_test;
    `uvm_component_utils(core_uart_base_test)

    core_uart_env env;

    function new(string name = "core_uart_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = core_uart_env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction
endclass : core_uart_base_test

// -----------------------------------------------------------------------------
// Test 1: Direct Core-to-UART Register Read & Write Integrity Test
// -----------------------------------------------------------------------------
class core_uart_direct_rw_test extends core_uart_base_test;
    `uvm_component_utils(core_uart_direct_rw_test)

    function new(string name = "core_uart_direct_rw_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        core_write_seq wr;
        core_read_seq  rd;

        phase.raise_objection(this);
        `uvm_info("TEST", "====================================================================", UVM_LOW)
        `uvm_info("TEST", "  TEST 1: DIRECT CORE READ/WRITE TO UART (ZERO AXI INTERCONNECT)    ", UVM_LOW)
        `uvm_info("TEST", "====================================================================", UVM_LOW)

        // 1. Direct Read from LSR
        rd = core_read_seq::type_id::create("rd_lsr_init");
        rd.read_addr = ADDR_LSR;
        rd.start(env.m_core_agent.sequencer);
        `uvm_info("TEST", $sformatf("Direct Read LSR: 0x%08h (THRE=%b DR=%b)", rd.read_data, rd.read_data[5], rd.read_data[0]), UVM_LOW)

        // 2. Direct Write to LCR (DLAB=1, 8N1)
        `uvm_info("TEST", "Direct Core Write LCR: 0x00000083 (DLAB=1)", UVM_LOW)
        wr = core_write_seq::type_id::create("wr_lcr");
        wr.write_addr = ADDR_LCR;
        wr.write_data = 32'h0000_0083;
        wr.start(env.m_core_agent.sequencer);

        // 3. Direct Write to BAUD (Divisor = 20)
        `uvm_info("TEST", "Direct Core Write Baud Divisor: 0x00000014 (20 decimal)", UVM_LOW)
        wr = core_write_seq::type_id::create("wr_baud");
        wr.write_addr = ADDR_BAUD;
        wr.write_data = 32'h0000_0014;
        wr.start(env.m_core_agent.sequencer);

        // 4. Direct Write to LCR (DLAB=0, Normal mode 8N1)
        `uvm_info("TEST", "Direct Core Write LCR: 0x00000003 (DLAB=0, 8N1)", UVM_LOW)
        wr = core_write_seq::type_id::create("wr_lcr_norm");
        wr.write_addr = ADDR_LCR;
        wr.write_data = 32'h0000_0003;
        wr.start(env.m_core_agent.sequencer);

        // 5. Direct Write to IER (Enable RX IRQ)
        `uvm_info("TEST", "Direct Core Write IER: 0x00000001 (Enable RX Interrupt)", UVM_LOW)
        wr = core_write_seq::type_id::create("wr_ier");
        wr.write_addr = ADDR_IER;
        wr.write_data = 32'h0000_0001;
        wr.start(env.m_core_agent.sequencer);

        #100ns;
        `uvm_info("TEST", "Direct Core read/write register test completed successfully", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass : core_uart_direct_rw_test

// -----------------------------------------------------------------------------
// Test 2: Direct Core-to-UART Transmit Test (Core Write -> Serial TX)
// -----------------------------------------------------------------------------
class core_uart_direct_tx_test extends core_uart_base_test;
    `uvm_component_utils(core_uart_direct_tx_test)

    function new(string name = "core_uart_direct_tx_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        core_uart_config_seq cfg_seq;
        core_uart_tx_seq     tx_seq;

        phase.raise_objection(this);
        `uvm_info("TEST", "====================================================================", UVM_LOW)
        `uvm_info("TEST", "  TEST 2: DIRECT CORE WRITE TO UART THR -> SERIAL TX MONITOR        ", UVM_LOW)
        `uvm_info("TEST", "====================================================================", UVM_LOW)

        // 1. Direct Core configures UART
        cfg_seq = core_uart_config_seq::type_id::create("cfg_seq");
        cfg_seq.baud_divisor = 16;
        cfg_seq.start(env.m_core_agent.sequencer);

        env.m_uart_agent.monitor.set_baud_divisor(16);

        // 2. Direct Core writes string
        tx_seq = core_uart_tx_seq::type_id::create("tx_seq");
        tx_seq.msg = "CORE_DIRECT!";
        tx_seq.start(env.m_core_agent.sequencer);

        // Wait for all characters to be serialized out
        #40us;

        `uvm_info("TEST", "Direct Core TX test completed", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass : core_uart_direct_tx_test

// -----------------------------------------------------------------------------
// Test 3: Direct Core-to-UART Receive Test (Serial RX -> Direct Core Read RBR)
// -----------------------------------------------------------------------------
class core_uart_direct_rx_test extends core_uart_base_test;
    `uvm_component_utils(core_uart_direct_rx_test)

    function new(string name = "core_uart_direct_rx_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        core_uart_config_seq cfg_seq;
        uart_rx_drive_seq    rx_drv_seq;
        core_read_seq        rd;
        byte unsigned test_bytes[$] = '{8'h56, 8'h65, 8'h65, 8'h52, 8'h32}; // "VeeR2"

        phase.raise_objection(this);
        `uvm_info("TEST", "====================================================================", UVM_LOW)
        `uvm_info("TEST", "  TEST 3: SERIAL RX INJECTION -> DIRECT CORE READ FROM UART RBR      ", UVM_LOW)
        `uvm_info("TEST", "====================================================================", UVM_LOW)

        // 1. Direct Core configures UART
        cfg_seq = core_uart_config_seq::type_id::create("cfg_seq");
        cfg_seq.baud_divisor = 16;
        cfg_seq.start(env.m_core_agent.sequencer);

        // 2. Queue expected bytes into scoreboard
        foreach (test_bytes[i]) begin
            env.m_scoreboard.expect_rx_byte(test_bytes[i]);
        end

        fork
            // Thread A: UART VIP drives serial bytes into uart_rx
            begin
                rx_drv_seq = uart_rx_drive_seq::type_id::create("rx_drv_seq");
                rx_drv_seq.baud_divisor = 16;
                rx_drv_seq.bytes_to_send = test_bytes;
                rx_drv_seq.start(env.m_uart_agent.sequencer);
            end

            // Thread B: Core directly polls LSR and reads RBR
            begin
                foreach (test_bytes[i]) begin
                    // Poll LSR until DR (bit 0) == 1
                    do begin
                        rd = core_read_seq::type_id::create("rd_lsr");
                        rd.read_addr = ADDR_LSR;
                        rd.start(env.m_core_agent.sequencer);
                    end while (rd.read_data[0] == 1'b0);

                    // Direct Read RBR
                    rd = core_read_seq::type_id::create("rd_rbr");
                    rd.read_addr = ADDR_RBR;
                    rd.start(env.m_core_agent.sequencer);
                    `uvm_info("TEST", $sformatf("Direct Core read RBR retrieved: 0x%02h ('%c')",
                                                rd.read_data[7:0], rd.read_data[7:0]), UVM_LOW)
                end
            end
        join

        #5us;
        `uvm_info("TEST", "Direct Core RX test completed", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass : core_uart_direct_rx_test

// -----------------------------------------------------------------------------
// Test 4: Direct Core Full Duplex Test
// -----------------------------------------------------------------------------
class core_uart_direct_duplex_test extends core_uart_base_test;
    `uvm_component_utils(core_uart_direct_duplex_test)

    function new(string name = "core_uart_direct_duplex_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        core_uart_config_seq cfg_seq;
        core_uart_tx_seq     tx_seq;
        uart_rx_drive_seq    rx_drv_seq;
        core_read_seq        rd;
        byte unsigned rx_payload[$] = '{8'h52, 8'h58, 8'h4f, 8'h4b}; // "RXOK"

        phase.raise_objection(this);
        `uvm_info("TEST", "====================================================================", UVM_LOW)
        `uvm_info("TEST", "  TEST 4: DIRECT CORE FULL DUPLEX (CONCURRENT READ/WRITE & SERIAL)  ", UVM_LOW)
        `uvm_info("TEST", "====================================================================", UVM_LOW)

        // 1. Direct Core configures UART
        cfg_seq = core_uart_config_seq::type_id::create("cfg_seq");
        cfg_seq.baud_divisor = 16;
        cfg_seq.start(env.m_core_agent.sequencer);

        env.m_uart_agent.monitor.set_baud_divisor(16);

        foreach (rx_payload[i]) begin
            env.m_scoreboard.expect_rx_byte(rx_payload[i]);
        end

        fork
            // Thread 1: Core direct write TX
            begin
                tx_seq = core_uart_tx_seq::type_id::create("tx_seq");
                tx_seq.msg = "TXOK";
                tx_seq.start(env.m_core_agent.sequencer);
            end

            // Thread 2: UART Serial driver
            begin
                rx_drv_seq = uart_rx_drive_seq::type_id::create("rx_drv_seq");
                rx_drv_seq.baud_divisor = 16;
                rx_drv_seq.bytes_to_send = rx_payload;
                rx_drv_seq.start(env.m_uart_agent.sequencer);
            end

            // Thread 3: Core direct read RX
            begin
                foreach (rx_payload[i]) begin
                    do begin
                        rd = core_read_seq::type_id::create("rd_lsr");
                        rd.read_addr = ADDR_LSR;
                        rd.start(env.m_core_agent.sequencer);
                    end while (rd.read_data[0] == 1'b0);

                    rd = core_read_seq::type_id::create("rd_rbr");
                    rd.read_addr = ADDR_RBR;
                    rd.start(env.m_core_agent.sequencer);
                end
            end
        join

        #25us;
        `uvm_info("TEST", "Direct Core Full Duplex test completed", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass : core_uart_direct_duplex_test

// -----------------------------------------------------------------------------
// Test 5: UNIFIED SINGLE UVM TESTBENCH (Runs All Testcases End-to-End)
// -----------------------------------------------------------------------------
class core_uart_unified_test extends core_uart_base_test;
    `uvm_component_utils(core_uart_unified_test)

    typedef struct {
        int    tc_num;
        string desc;
        string input_given;
        string exp_output;
        string got_output;
        bit    passed;
    } tc_report_t;

    tc_report_t results_q[$];
    int unsigned num_passed = 0;
    int unsigned num_failed = 0;

    function new(string name = "core_uart_unified_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void record_tc(int tc_num, string desc, string input_given, string exp_output, string got_output, bit passed);
        tc_report_t r;
        r.tc_num      = tc_num;
        r.desc        = desc;
        r.input_given = input_given;
        r.exp_output  = exp_output;
        r.got_output  = got_output;
        r.passed      = passed;
        results_q.push_back(r);
        if (passed) num_passed++;
        else        num_failed++;
    endfunction

    virtual task run_phase(uvm_phase phase);
        core_write_seq       wr;
        core_read_seq        rd;
        core_uart_config_seq cfg_seq;
        core_uart_tx_seq     tx_seq;
        uart_rx_drive_seq    rx_drv_seq;
        byte unsigned        rx_bytes[$];
        byte unsigned        duplex_rx[$];
        byte unsigned        hex_patterns[$];
        int prev_tx_matches, prev_rx_matches;
        bit step_pass;

        phase.raise_objection(this);

        `uvm_info("UNIFIED_TB", "================================================================================", UVM_NONE)
        `uvm_info("UNIFIED_TB", "   STARTING UNIFIED DIRECT CORE-TO-UART UVM TESTBENCH (ALL TESTS IN ONE TB)     ", UVM_NONE)
        `uvm_info("UNIFIED_TB", "================================================================================", UVM_NONE)

        // ---------------------------------------------------------------------
        // STAGE 1: DIRECT CORE REGISTER READ/WRITE TRANSACTIONS (NO AXI INTERCONNECT)
        // ---------------------------------------------------------------------
        `uvm_info("UNIFIED_TB", ">>> STAGE 1: Direct Core Register Read & Write Integrity Tests", UVM_LOW)

        // TC 1: Read Initial LSR
        rd = core_read_seq::type_id::create("rd_lsr_init");
        rd.read_addr = ADDR_LSR;
        rd.start(env.m_core_agent.sequencer);
        step_pass = (rd.read_data[5] === 1'b1 && rd.read_data[0] === 1'b0);
        record_tc(1, "Direct Read Initial LSR (0x14)", "Addr: 0x14",
                  "LSR[5]=1(THRE), DR=0 (0x60)",
                  $sformatf("LSR=0x%08h (THRE=%b DR=%b)", rd.read_data, rd.read_data[5], rd.read_data[0]),
                  step_pass);

        // TC 2: Write LCR to enable DLAB
        wr = core_write_seq::type_id::create("wr_lcr_dlab");
        wr.write_addr = ADDR_LCR;
        wr.write_data = 32'h0000_0083; // DLAB=1, 8N1
        wr.start(env.m_core_agent.sequencer);
        step_pass = (wr.resp == CORE_RESP_OKAY);
        record_tc(2, "Direct Write LCR (DLAB=1, 8N1)", "Addr: 0x0C Data: 0x00000083",
                  "BRESP=OKAY (2'b00)", $sformatf("BRESP=%s", wr.resp.name()), step_pass);

        // TC 3: Write BAUD divisor
        wr = core_write_seq::type_id::create("wr_baud");
        wr.write_addr = ADDR_BAUD;
        wr.write_data = 32'h0000_0010; // Divisor = 16
        wr.start(env.m_core_agent.sequencer);
        step_pass = (wr.resp == CORE_RESP_OKAY);
        record_tc(3, "Direct Write Baud Divisor (16)", "Addr: 0x08 Data: 0x00000010",
                  "BRESP=OKAY (2'b00)", $sformatf("BRESP=%s", wr.resp.name()), step_pass);

        // TC 4: Write LCR normal mode
        wr = core_write_seq::type_id::create("wr_lcr_norm");
        wr.write_addr = ADDR_LCR;
        wr.write_data = 32'h0000_0003; // DLAB=0, 8N1
        wr.start(env.m_core_agent.sequencer);
        step_pass = (wr.resp == CORE_RESP_OKAY);
        record_tc(4, "Direct Write LCR (DLAB=0, 8N1)", "Addr: 0x0C Data: 0x00000003",
                  "BRESP=OKAY (2'b00)", $sformatf("BRESP=%s", wr.resp.name()), step_pass);

        // TC 5: Write IER enable RX IRQ
        wr = core_write_seq::type_id::create("wr_ier");
        wr.write_addr = ADDR_IER;
        wr.write_data = 32'h0000_0001; // Enable RX IRQ
        wr.start(env.m_core_agent.sequencer);
        step_pass = (wr.resp == CORE_RESP_OKAY);
        record_tc(5, "Direct Write IER (Enable RX IRQ)", "Addr: 0x04 Data: 0x00000001",
                  "BRESP=OKAY (2'b00)", $sformatf("BRESP=%s", wr.resp.name()), step_pass);

        // ---------------------------------------------------------------------
        // STAGE 2: DIRECT CORE WRITE TO UART THR -> SERIAL TX
        // ---------------------------------------------------------------------
        `uvm_info("UNIFIED_TB", ">>> STAGE 2: Direct Core Transmit (Core Write -> Serial TX)", UVM_LOW)
        env.m_uart_agent.monitor.set_baud_divisor(16);
        prev_tx_matches = env.m_scoreboard.num_tx_matches;

        tx_seq = core_uart_tx_seq::type_id::create("tx_seq_stage2");
        tx_seq.msg = "CORE_TX_DIRECT";
        tx_seq.start(env.m_core_agent.sequencer);
        #30us;

        step_pass = ((env.m_scoreboard.num_tx_matches - prev_tx_matches) == tx_seq.msg.len()) &&
                    (env.m_scoreboard.num_tx_mismatches == 0);
        record_tc(6, "Direct Core TX: \"CORE_TX_DIRECT\"",
                  $sformatf("14 Direct Writes to THR ('%s')", tx_seq.msg),
                  "14 Serial TX Matches (0 mismatches)",
                  $sformatf("%0d TX Matches, %0d Mismatches",
                            (env.m_scoreboard.num_tx_matches - prev_tx_matches),
                            env.m_scoreboard.num_tx_mismatches),
                  step_pass);

        // ---------------------------------------------------------------------
        // STAGE 3: SERIAL RX INJECTION -> DIRECT CORE READ FROM RBR
        // ---------------------------------------------------------------------
        `uvm_info("UNIFIED_TB", ">>> STAGE 3: Serial RX Injection -> Direct Core Read RBR", UVM_LOW)
        rx_bytes = '{8'h56, 8'h65, 8'h65, 8'h52, 8'h32, 8'h5f, 8'h4f, 8'h4b, 8'h21}; // "VeeR2_OK!"
        prev_rx_matches = env.m_scoreboard.num_rx_matches;

        foreach (rx_bytes[i]) begin
            env.m_scoreboard.expect_rx_byte(rx_bytes[i]);
        end

        fork
            begin
                rx_drv_seq = uart_rx_drive_seq::type_id::create("rx_drv_seq_stage3");
                rx_drv_seq.baud_divisor = 16;
                rx_drv_seq.bytes_to_send = rx_bytes;
                rx_drv_seq.start(env.m_uart_agent.sequencer);
            end
            begin
                foreach (rx_bytes[i]) begin
                    do begin
                        rd = core_read_seq::type_id::create("rd_lsr_rx3");
                        rd.read_addr = ADDR_LSR;
                        rd.start(env.m_core_agent.sequencer);
                    end while (rd.read_data[0] == 1'b0);

                    rd = core_read_seq::type_id::create("rd_rbr_rx3");
                    rd.read_addr = ADDR_RBR;
                    rd.start(env.m_core_agent.sequencer);
                end
            end
        join
        #5us;

        step_pass = ((env.m_scoreboard.num_rx_matches - prev_rx_matches) == rx_bytes.size()) &&
                    (env.m_scoreboard.num_rx_mismatches == 0);
        record_tc(7, "Direct Core RX: \"VeeR2_OK!\"",
                  "9 Serial Injections to uart_rx ('VeeR2_OK!')",
                  "9 Direct RBR Matches (0 mismatches)",
                  $sformatf("%0d RX Matches, %0d Mismatches",
                            (env.m_scoreboard.num_rx_matches - prev_rx_matches),
                            env.m_scoreboard.num_rx_mismatches),
                  step_pass);

        // ---------------------------------------------------------------------
        // STAGE 4: CONCURRENT FULL DUPLEX DIRECT OPERATION
        // ---------------------------------------------------------------------
        `uvm_info("UNIFIED_TB", ">>> STAGE 4: Concurrent Full-Duplex Direct Operation", UVM_LOW)
        duplex_rx = '{8'h52, 8'h58, 8'h5f, 8'h44, 8'h55, 8'h50, 8'h4c, 8'h45, 8'h58, 8'h5f, 8'h50, 8'h4b, 8'h54, 8'h21}; // "RX_DUPLEX_PKT!" (14 bytes)
        prev_tx_matches = env.m_scoreboard.num_tx_matches;
        prev_rx_matches = env.m_scoreboard.num_rx_matches;

        foreach (duplex_rx[i]) begin
            env.m_scoreboard.expect_rx_byte(duplex_rx[i]);
        end

        fork
            begin
                tx_seq = core_uart_tx_seq::type_id::create("tx_seq_duplex");
                tx_seq.msg = "TX_DUPLEX_PKT!"; // 14 bytes
                tx_seq.start(env.m_core_agent.sequencer);
            end
            begin
                rx_drv_seq = uart_rx_drive_seq::type_id::create("rx_drv_duplex");
                rx_drv_seq.baud_divisor = 16;
                rx_drv_seq.bytes_to_send = duplex_rx;
                rx_drv_seq.start(env.m_uart_agent.sequencer);
            end
            begin
                foreach (duplex_rx[i]) begin
                    do begin
                        rd = core_read_seq::type_id::create("rd_lsr_dup");
                        rd.read_addr = ADDR_LSR;
                        rd.start(env.m_core_agent.sequencer);
                    end while (rd.read_data[0] == 1'b0);

                    rd = core_read_seq::type_id::create("rd_rbr_dup");
                    rd.read_addr = ADDR_RBR;
                    rd.start(env.m_core_agent.sequencer);
                end
            end
        join
        #35us;

        step_pass = ((env.m_scoreboard.num_tx_matches - prev_tx_matches) == 14) &&
                    ((env.m_scoreboard.num_rx_matches - prev_rx_matches) == 14) &&
                    (env.m_scoreboard.num_tx_mismatches == 0) &&
                    (env.m_scoreboard.num_rx_mismatches == 0);
        record_tc(8, "Direct Core Full Duplex (Simultaneous)",
                  "14 TX Writes + 14 RX Serial Injections",
                  "28 Concurrent Matches (14 TX + 14 RX)",
                  $sformatf("%0d TX Matches + %0d RX Matches",
                            (env.m_scoreboard.num_tx_matches - prev_tx_matches),
                            (env.m_scoreboard.num_rx_matches - prev_rx_matches)),
                  step_pass);

        // ---------------------------------------------------------------------
        // STAGE 5: HIGH-DENSITY BYTE PATTERN DIRECT SWEEP STRESS TEST
        // ---------------------------------------------------------------------
        `uvm_info("UNIFIED_TB", ">>> STAGE 5: High-Density Byte Pattern Direct Sweep Stress Test", UVM_LOW)
        hex_patterns = '{8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77, 8'h88,
                         8'h99, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hA5, 8'h5A};
        prev_tx_matches = env.m_scoreboard.num_tx_matches;
        prev_rx_matches = env.m_scoreboard.num_rx_matches;

        // 5.1: Core direct writes 16 hex patterns to THR -> verified by Serial TX Monitor
        for (int i = 0; i < hex_patterns.size(); i++) begin
            do begin
                rd = core_read_seq::type_id::create("rd_lsr_pat");
                rd.read_addr = ADDR_LSR;
                rd.start(env.m_core_agent.sequencer);
            end while (rd.read_data[5] == 1'b0);

            wr = core_write_seq::type_id::create("wr_thr_pat");
            wr.write_addr = ADDR_THR;
            wr.write_data = {24'h000000, hex_patterns[i]};
            wr.start(env.m_core_agent.sequencer);
        end
        #40us; // Wait for all 16 TX bytes to serialize

        // 5.2: Serial VIP injects 16 hex patterns -> verified by Core RBR Read
        foreach (hex_patterns[i]) begin
            env.m_scoreboard.expect_rx_byte(hex_patterns[i]);
        end

        fork
            begin
                rx_drv_seq = uart_rx_drive_seq::type_id::create("rx_drv_pat");
                rx_drv_seq.baud_divisor = 16;
                rx_drv_seq.bytes_to_send = hex_patterns;
                rx_drv_seq.start(env.m_uart_agent.sequencer);
            end
            begin
                foreach (hex_patterns[i]) begin
                    do begin
                        rd = core_read_seq::type_id::create("rd_lsr_pat_rx");
                        rd.read_addr = ADDR_LSR;
                        rd.start(env.m_core_agent.sequencer);
                    end while (rd.read_data[0] == 1'b0);

                    rd = core_read_seq::type_id::create("rd_rbr_pat_rx");
                    rd.read_addr = ADDR_RBR;
                    rd.start(env.m_core_agent.sequencer);
                end
            end
        join
        #5us;

        step_pass = ((env.m_scoreboard.num_tx_matches - prev_tx_matches) == hex_patterns.size()) &&
                    ((env.m_scoreboard.num_rx_matches - prev_rx_matches) == hex_patterns.size()) &&
                    (env.m_scoreboard.num_tx_mismatches == 0) &&
                    (env.m_scoreboard.num_rx_mismatches == 0);
        record_tc(9, "Direct Core Hex Pattern Data Sweep",
                  "16 Hex Patterns TX & RX (0x11..0x5A)",
                  "32 Pattern Matches (16 TX + 16 RX)",
                  $sformatf("%0d TX Matches + %0d RX Matches",
                            (env.m_scoreboard.num_tx_matches - prev_tx_matches),
                            (env.m_scoreboard.num_rx_matches - prev_rx_matches)),
                  step_pass);

        #100ns;
        print_summary_table();
        phase.drop_objection(this);
    endtask

    virtual function void print_summary_table();
        $display("");
        $display("====================================================================================================================================================");
        $display("                                    UNIFIED DIRECT CORE-TO-UART UVM TESTBENCH VERIFICATION REPORT                                   ");
        $display("                                               (ZERO AXI INTERCONNECT IN BETWEEN)                                                   ");
        $display("====================================================================================================================================================");
        $display(" TC # | Testcase Description                      | Input Given                    | Expected Output                | Actual Output                  | Status ");
        $display("----------------------------------------------------------------------------------------------------------------------------------------------------");
        foreach (results_q[i]) begin
            string status_str = results_q[i].passed ? "PASSED" : "FAILED";
            $display("  %-3d | %-41s | %-30s | %-30s | %-30s | %s",
                     results_q[i].tc_num,
                     results_q[i].desc,
                     results_q[i].input_given,
                     results_q[i].exp_output,
                     results_q[i].got_output,
                     status_str);
        end
        $display("====================================================================================================================================================");
        $display("  TOTAL TESTCASES RUN : %0d", results_q.size());
        $display("  TESTCASES PASSED    : %0d", num_passed);
        $display("  TESTCASES FAILED    : %0d", num_failed);
        $display("  SUCCESS RATE        : %0.1f%%", (real'(num_passed) / real'(results_q.size())) * 100.0);
        if (num_failed == 0) begin
            $display("  FINAL STATUS        : *** ALL TESTCASES PASSED SUCCESSFULLY! ***");
        end else begin
            $display("  FINAL STATUS        : *** TESTBENCH HAS FAILED TESTCASES ***");
        end
        $display("====================================================================================================================================================");
        $display("");
    endfunction
endclass : core_uart_unified_test

`endif // CORE_UART_TESTS_SV
