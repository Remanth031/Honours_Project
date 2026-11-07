// =============================================================================
// core_uart_sequences.sv – Direct Core-to-UART UVM Sequences
// =============================================================================
`ifndef CORE_UART_SEQUENCES_SV
`define CORE_UART_SEQUENCES_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import core_types_pkg::*;
import uart_types_pkg::*;
import core_vip_pkg::*;
import uart_vip_pkg::*;

// UART Register Offsets (Direct 5-bit register addresses)
parameter bit [4:0] ADDR_RBR  = 5'h00; // Read when DLAB=0
parameter bit [4:0] ADDR_THR  = 5'h00; // Write when DLAB=0
parameter bit [4:0] ADDR_IER  = 5'h04;
parameter bit [4:0] ADDR_BAUD = 5'h08; // R/W when DLAB=1
parameter bit [4:0] ADDR_LCR  = 5'h0C;
parameter bit [4:0] ADDR_LSR  = 5'h14;

// -----------------------------------------------------------------------------
// Sequence 1: Direct Core Write
// -----------------------------------------------------------------------------
class core_write_seq extends uvm_sequence #(core_seq_item);
    `uvm_object_utils(core_write_seq)

    rand bit [4:0]  write_addr;
    rand bit [31:0] write_data;
    core_resp_e     resp;

    function new(string name = "core_write_seq");
        super.new(name);
    endfunction

    virtual task body();
        core_seq_item item;
        item = core_seq_item::type_id::create("core_wr_item");
        start_item(item);
        item.op    = CORE_WRITE;
        item.addr  = write_addr;
        item.data  = write_data;
        item.strb  = 4'b1111;
        item.delay = 0;
        finish_item(item);
        resp = item.resp;
    endtask
endclass : core_write_seq

// -----------------------------------------------------------------------------
// Sequence 2: Direct Core Read
// -----------------------------------------------------------------------------
class core_read_seq extends uvm_sequence #(core_seq_item);
    `uvm_object_utils(core_read_seq)

    rand bit [4:0]  read_addr;
    bit [31:0]      read_data;
    core_resp_e     resp;

    function new(string name = "core_read_seq");
        super.new(name);
    endfunction

    virtual task body();
        core_seq_item item;
        item = core_seq_item::type_id::create("core_rd_item");
        start_item(item);
        item.op    = CORE_READ;
        item.addr  = read_addr;
        item.delay = 0;
        finish_item(item);
        read_data = item.data;
        resp      = item.resp;
    endtask
endclass : core_read_seq

// -----------------------------------------------------------------------------
// Sequence 3: Core Configures UART Baud Rate & Line Control Directly
// -----------------------------------------------------------------------------
class core_uart_config_seq extends uvm_sequence #(core_seq_item);
    `uvm_object_utils(core_uart_config_seq)

    int unsigned baud_divisor = 16;

    function new(string name = "core_uart_config_seq");
        super.new(name);
    endfunction

    virtual task body();
        core_write_seq wr;

        `uvm_info("CORE_CFG", $sformatf("Direct Core configuring UART baud divisor = %0d", baud_divisor), UVM_LOW)

        // 1. Enable DLAB (LCR bit 7 = 1)
        wr = core_write_seq::type_id::create("wr_dlab_en");
        wr.write_addr = ADDR_LCR;
        wr.write_data = 32'h0000_0083; // DLAB=1, 8N1
        wr.start(m_sequencer);

        // 2. Set Baud Divisor
        wr = core_write_seq::type_id::create("wr_baud");
        wr.write_addr = ADDR_BAUD;
        wr.write_data = baud_divisor;
        wr.start(m_sequencer);

        // 3. Disable DLAB (Normal Mode, 8N1)
        wr = core_write_seq::type_id::create("wr_dlab_dis");
        wr.write_addr = ADDR_LCR;
        wr.write_data = 32'h0000_0003; // DLAB=0, 8N1
        wr.start(m_sequencer);

        // 4. Enable Receiver Interrupt (IER bit 0 = 1)
        wr = core_write_seq::type_id::create("wr_ier");
        wr.write_addr = ADDR_IER;
        wr.write_data = 32'h0000_0001;
        wr.start(m_sequencer);

        `uvm_info("CORE_CFG", "Direct Core UART configuration finished", UVM_LOW)
    endtask
endclass : core_uart_config_seq

// -----------------------------------------------------------------------------
// Sequence 4: Core Direct Writes String of Bytes into THR
// -----------------------------------------------------------------------------
class core_uart_tx_seq extends uvm_sequence #(core_seq_item);
    `uvm_object_utils(core_uart_tx_seq)

    string msg = "DIRECT_CORE_PASS";

    function new(string name = "core_uart_tx_seq");
        super.new(name);
    endfunction

    virtual task body();
        core_write_seq wr;
        core_read_seq  rd;

        `uvm_info("CORE_TX", $sformatf("Core directly transmitting message: \"%s\"", msg), UVM_LOW)

        for (int i = 0; i < msg.len(); i++) begin
            bit [7:0] ch = msg[i];

            // Direct read: Poll LSR[5] (THRE == 1)
            do begin
                rd = core_read_seq::type_id::create("rd_lsr");
                rd.read_addr = ADDR_LSR;
                rd.start(m_sequencer);
            end while (rd.read_data[5] == 1'b0);

            // Direct write: Write character to THR
            wr = core_write_seq::type_id::create("wr_thr");
            wr.write_addr = ADDR_THR;
            wr.write_data = {24'h000000, ch};
            wr.start(m_sequencer);
            `uvm_info("CORE_TX", $sformatf("Core wrote char '%c' (0x%02h) directly to THR", ch, ch), UVM_MEDIUM)
        end
    endtask
endclass : core_uart_tx_seq

// -----------------------------------------------------------------------------
// Sequence 5: UART Serial VIP Injects Bytes into uart_rx
// -----------------------------------------------------------------------------
class uart_rx_drive_seq extends uvm_sequence #(uart_seq_item);
    `uvm_object_utils(uart_rx_drive_seq)

    byte unsigned bytes_to_send[$];
    int unsigned baud_divisor = 16;

    function new(string name = "uart_rx_drive_seq");
        super.new(name);
    endfunction

    virtual task body();
        uart_seq_item item;
        foreach (bytes_to_send[i]) begin
            item = uart_seq_item::type_id::create("uart_item");
            start_item(item);
            item.payload      = bytes_to_send[i];
            item.baud_divisor = baud_divisor;
            item.parity       = UART_PARITY_NONE;
            item.stop_bits    = UART_STOP_1BIT;
            finish_item(item);
        end
    endtask
endclass : uart_rx_drive_seq

`endif // CORE_UART_SEQUENCES_SV
