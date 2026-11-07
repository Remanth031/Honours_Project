// =============================================================================
// soc_tests.sv – UVM Testcases for Subsystem Verification
// =============================================================================
`ifndef SOC_TESTS_SV
`define SOC_TESTS_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_types_pkg::*;
import uart_types_pkg::*;
import axi_vip_pkg::*;
import uart_vip_pkg::*;
import soc_env_pkg::*;
`include "soc_sequences.sv"

// -----------------------------------------------------------------------------
// Base Test
// -----------------------------------------------------------------------------
class soc_base_test extends uvm_test;
    `uvm_component_utils(soc_base_test)

    soc_env env;

    function new(string name = "soc_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = soc_env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction
endclass : soc_base_test

// -----------------------------------------------------------------------------
// Test 1: AXI Register Read & Write Integrity Test
// -----------------------------------------------------------------------------
class soc_reg_rw_test extends soc_base_test;
    `uvm_component_utils(soc_reg_rw_test)

    function new(string name = "soc_reg_rw_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        axi_write_seq wr;
        axi_read_seq  rd;

        phase.raise_objection(this);
        `uvm_info("TEST", "====================================================================", UVM_LOW)
        `uvm_info("TEST", "    STARTING TEST 1: AXI INTERCONNECT & UART REGISTER READ/WRITE    ", UVM_LOW)
        `uvm_info("TEST", "====================================================================", UVM_LOW)

        // 1. Initial LSR Read (Check Line Status)
        rd = axi_read_seq::type_id::create("rd_lsr_init");
        rd.read_addr = UART_LSR_ADDR;
        rd.start(env.m_axi_agent.sequencer);
        `uvm_info("TEST", $sformatf("Read LSR: 0x%08h (THRE=%b DR=%b)", rd.read_data, rd.read_data[5], rd.read_data[0]), UVM_LOW)

        // 2. Write & Read LCR (Line Control Register)
        `uvm_info("TEST", "Writing LCR: 0x00000083 (DLAB=1, 8-bit, 2 stop bits)", UVM_LOW)
        wr = axi_write_seq::type_id::create("wr_lcr");
        wr.write_addr = UART_LCR_ADDR;
        wr.write_data = 32'h0000_0083;
        wr.start(env.m_axi_agent.sequencer);

        // 3. Write & Read Baud Divisor Register (while DLAB=1)
        `uvm_info("TEST", "Writing Baud Divisor: 0x00000018 (24 decimal)", UVM_LOW)
        wr = axi_write_seq::type_id::create("wr_baud");
        wr.write_addr = UART_BAUD_ADDR;
        wr.write_data = 32'h0000_0018;
        wr.start(env.m_axi_agent.sequencer);

        // 4. Switch DLAB back to 0
        `uvm_info("TEST", "Writing LCR: 0x00000000 (DLAB=0)", UVM_LOW)
        wr = axi_write_seq::type_id::create("wr_lcr_norm");
        wr.write_addr = UART_LCR_ADDR;
        wr.write_data = 32'h0000_0000;
        wr.start(env.m_axi_agent.sequencer);

        // 5. Write & Read IER (Interrupt Enable Register)
        `uvm_info("TEST", "Writing IER: 0x00000001 (Enable RX IRQ)", UVM_LOW)
        wr = axi_write_seq::type_id::create("wr_ier");
        wr.write_addr = UART_IER_ADDR;
        wr.write_data = 32'h0000_0001;
        wr.start(env.m_axi_agent.sequencer);

        #100ns;
        `uvm_info("TEST", "All AXI register read/write operations completed successfully", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass : soc_reg_rw_test

// -----------------------------------------------------------------------------
// Test 2: UART Transmit End-to-End Test (AXI -> Interconnect -> UART -> Serial TX)
// -----------------------------------------------------------------------------
class soc_uart_tx_test extends soc_base_test;
    `uvm_component_utils(soc_uart_tx_test)

    function new(string name = "soc_uart_tx_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        uart_config_seq cfg_seq;
        soc_uart_tx_seq tx_seq;

        phase.raise_objection(this);
        `uvm_info("TEST", "====================================================================", UVM_LOW)
        `uvm_info("TEST", "    STARTING TEST 2: UART TRANSMIT END-TO-END VERIFICATION          ", UVM_LOW)
        `uvm_info("TEST", "====================================================================", UVM_LOW)

        // 1. Configure UART with Baud Divisor = 16
        cfg_seq = uart_config_seq::type_id::create("cfg_seq");
        cfg_seq.baud_divisor = 16;
        cfg_seq.start(env.m_axi_agent.sequencer);

        env.m_uart_agent.monitor.set_baud_divisor(16);

        // 2. Transmit String through Interconnect
        tx_seq = soc_uart_tx_seq::type_id::create("tx_seq");
        tx_seq.msg = "RISCV_UART!";
        tx_seq.start(env.m_axi_agent.sequencer);

        // Wait for all characters to be serialized and monitored
        #35us;

        `uvm_info("TEST", "UART TX test sequence execution completed", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass : soc_uart_tx_test

// -----------------------------------------------------------------------------
// Test 3: UART Receive End-to-End Test (Serial RX -> UART -> Interconnect -> AXI Read)
// -----------------------------------------------------------------------------
class soc_uart_rx_test extends soc_base_test;
    `uvm_component_utils(soc_uart_rx_test)

    function new(string name = "soc_uart_rx_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        uart_config_seq   cfg_seq;
        uart_rx_drive_seq rx_drv_seq;
        axi_read_seq      rd;
        byte unsigned test_bytes[$] = '{8'h41, 8'h42, 8'h43, 8'h31, 8'h32, 8'h33}; // "ABC123"

        phase.raise_objection(this);
        `uvm_info("TEST", "====================================================================", UVM_LOW)
        `uvm_info("TEST", "    STARTING TEST 3: UART RECEIVE END-TO-END VERIFICATION           ", UVM_LOW)
        `uvm_info("TEST", "====================================================================", UVM_LOW)

        // 1. Configure UART
        cfg_seq = uart_config_seq::type_id::create("cfg_seq");
        cfg_seq.baud_divisor = 16;
        cfg_seq.start(env.m_axi_agent.sequencer);

        // 2. Push expected bytes to scoreboard and drive serial RX
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

            // Thread B: AXI Master polls LSR[0] (DR) and reads RBR for each byte
            begin
                foreach (test_bytes[i]) begin
                    // Poll LSR until DR == 1
                    do begin
                        rd = axi_read_seq::type_id::create("rd_lsr");
                        rd.read_addr = UART_LSR_ADDR;
                        rd.start(env.m_axi_agent.sequencer);
                    end while (rd.read_data[0] == 1'b0);

                    // Read byte from RBR
                    rd = axi_read_seq::type_id::create("rd_rbr");
                    rd.read_addr = UART_RBR_ADDR;
                    rd.start(env.m_axi_agent.sequencer);
                    `uvm_info("TEST", $sformatf("AXI read RBR retrieved: 0x%02h ('%c')",
                                                rd.read_data[7:0], rd.read_data[7:0]), UVM_LOW)
                end
            end
        join

        #5us;
        `uvm_info("TEST", "UART RX test sequence execution completed", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass : soc_uart_rx_test

// -----------------------------------------------------------------------------
// Test 4: Full Duplex Concurrent TX & RX Test
// -----------------------------------------------------------------------------
class soc_full_duplex_test extends soc_base_test;
    `uvm_component_utils(soc_full_duplex_test)

    function new(string name = "soc_full_duplex_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        uart_config_seq   cfg_seq;
        soc_uart_tx_seq   tx_seq;
        uart_rx_drive_seq rx_drv_seq;
        axi_read_seq      rd;
        byte unsigned rx_payload[$] = '{8'h54, 8'h45, 8'h53, 8'h54}; // "TEST"

        phase.raise_objection(this);
        `uvm_info("TEST", "====================================================================", UVM_LOW)
        `uvm_info("TEST", "    STARTING TEST 4: FULL DUPLEX CONCURRENT TX & RX VERIFICATION    ", UVM_LOW)
        `uvm_info("TEST", "====================================================================", UVM_LOW)

        // 1. Configure UART
        cfg_seq = uart_config_seq::type_id::create("cfg_seq");
        cfg_seq.baud_divisor = 16;
        cfg_seq.start(env.m_axi_agent.sequencer);

        env.m_uart_agent.monitor.set_baud_divisor(16);

        foreach (rx_payload[i]) begin
            env.m_scoreboard.expect_rx_byte(rx_payload[i]);
        end

        fork
            // TX Path
            begin
                tx_seq = soc_uart_tx_seq::type_id::create("tx_seq");
                tx_seq.msg = "PING";
                tx_seq.start(env.m_axi_agent.sequencer);
            end

            // RX Path (Serial Driver)
            begin
                rx_drv_seq = uart_rx_drive_seq::type_id::create("rx_drv_seq");
                rx_drv_seq.baud_divisor = 16;
                rx_drv_seq.bytes_to_send = rx_payload;
                rx_drv_seq.start(env.m_uart_agent.sequencer);
            end

            // RX Path (AXI Reader)
            begin
                foreach (rx_payload[i]) begin
                    do begin
                        rd = axi_read_seq::type_id::create("rd_lsr");
                        rd.read_addr = UART_LSR_ADDR;
                        rd.start(env.m_axi_agent.sequencer);
                    end while (rd.read_data[0] == 1'b0);

                    rd = axi_read_seq::type_id::create("rd_rbr");
                    rd.read_addr = UART_RBR_ADDR;
                    rd.start(env.m_axi_agent.sequencer);
                end
            end
        join

        #25us;
        `uvm_info("TEST", "Full Duplex test completed", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass : soc_full_duplex_test

`endif // SOC_TESTS_SV
