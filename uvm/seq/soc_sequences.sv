// =============================================================================
// soc_sequences.sv – UVM Sequences for AXI Interconnect & UART Verification
// =============================================================================
`ifndef SOC_SEQUENCES_SV
`define SOC_SEQUENCES_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_types_pkg::*;
import uart_types_pkg::*;
import axi_vip_pkg::*;
import uart_vip_pkg::*;

// Address Map Constants
parameter bit [31:0] UART_BASE_ADDR = 32'h2003_0000;
parameter bit [31:0] UART_RBR_ADDR  = 32'h2003_0000;
parameter bit [31:0] UART_THR_ADDR  = 32'h2003_0000;
parameter bit [31:0] UART_IER_ADDR  = 32'h2003_0004;
parameter bit [31:0] UART_BAUD_ADDR = 32'h2003_0008;
parameter bit [31:0] UART_LCR_ADDR  = 32'h2003_000C;
parameter bit [31:0] UART_LSR_ADDR  = 32'h2003_0014;

// -----------------------------------------------------------------------------
// Sequence 1: Single AXI Write
// -----------------------------------------------------------------------------
class axi_write_seq extends uvm_sequence #(axi_seq_item);
    `uvm_object_utils(axi_write_seq)

    rand bit [31:0] write_addr;
    rand bit [31:0] write_data;

    function new(string name = "axi_write_seq");
        super.new(name);
    endfunction

    virtual task body();
        axi_seq_item item;
        item = axi_seq_item::type_id::create("axi_wr_item");
        start_item(item);
        item.rw      = AXI_WRITE;
        item.addr    = write_addr;
        item.len     = 0;
        item.data    = new[1];
        item.data[0] = write_data;
        item.strb    = new[1];
        item.strb[0] = 4'b1111;
        item.resp    = new[1];
        finish_item(item);
    endtask
endclass : axi_write_seq

// -----------------------------------------------------------------------------
// Sequence 2: Single AXI Read
// -----------------------------------------------------------------------------
class axi_read_seq extends uvm_sequence #(axi_seq_item);
    `uvm_object_utils(axi_read_seq)

    rand bit [31:0] read_addr;
    bit [31:0]      read_data;

    function new(string name = "axi_read_seq");
        super.new(name);
    endfunction

    virtual task body();
        axi_seq_item item;
        item = axi_seq_item::type_id::create("axi_rd_item");
        start_item(item);
        item.rw   = AXI_READ;
        item.addr = read_addr;
        item.len  = 0;
        item.resp = new[1];
        finish_item(item);
        read_data = item.data[0];
    endtask
endclass : axi_read_seq

// -----------------------------------------------------------------------------
// Sequence 3: Configure UART Baud Rate and Line Control
// -----------------------------------------------------------------------------
class uart_config_seq extends uvm_sequence #(axi_seq_item);
    `uvm_object_utils(uart_config_seq)

    int unsigned baud_divisor = 16;

    function new(string name = "uart_config_seq");
        super.new(name);
    endfunction

    virtual task body();
        axi_write_seq wr;

        `uvm_info("UART_CFG_SEQ", $sformatf("Configuring UART with baud divisor = %0d", baud_divisor), UVM_LOW)

        // 1. Enable DLAB (LCR bit 7 = 1)
        wr = axi_write_seq::type_id::create("wr_dlab_en");
        wr.write_addr = UART_LCR_ADDR;
        wr.write_data = 32'h0000_0080;
        wr.start(m_sequencer);

        // 2. Set Baud Rate Divisor
        wr = axi_write_seq::type_id::create("wr_baud");
        wr.write_addr = UART_BAUD_ADDR;
        wr.write_data = baud_divisor;
        wr.start(m_sequencer);

        // 3. Disable DLAB, Set 8 data bits, 1 stop bit, no parity (LCR = 0x00)
        wr = axi_write_seq::type_id::create("wr_dlab_dis");
        wr.write_addr = UART_LCR_ADDR;
        wr.write_data = 32'h0000_0000;
        wr.start(m_sequencer);

        // 4. Enable Receiver Interrupt (IER bit 0 = 1)
        wr = axi_write_seq::type_id::create("wr_ier");
        wr.write_addr = UART_IER_ADDR;
        wr.write_data = 32'h0000_0001;
        wr.start(m_sequencer);

        `uvm_info("UART_CFG_SEQ", "UART Configuration Complete", UVM_LOW)
    endtask
endclass : uart_config_seq

// -----------------------------------------------------------------------------
// Sequence 4: Transmit String of Characters through AXI Interconnect into UART THR
// -----------------------------------------------------------------------------
class soc_uart_tx_seq extends uvm_sequence #(axi_seq_item);
    `uvm_object_utils(soc_uart_tx_seq)

    string msg = "VCS_UVM_PASS";

    function new(string name = "soc_uart_tx_seq");
        super.new(name);
    endfunction

    virtual task body();
        axi_write_seq wr;
        axi_read_seq  rd;

        `uvm_info("TX_SEQ", $sformatf("Starting AXI writes for message: \"%s\"", msg), UVM_LOW)

        for (int i = 0; i < msg.len(); i++) begin
            bit [7:0] ch = msg[i];

            // Wait if TX FIFO is full (poll LSR[5] == 1)
            do begin
                rd = axi_read_seq::type_id::create("rd_lsr");
                rd.read_addr = UART_LSR_ADDR;
                rd.start(m_sequencer);
            end while (rd.read_data[5] == 1'b0);

            // Write character to THR
            wr = axi_write_seq::type_id::create("wr_thr");
            wr.write_addr = UART_THR_ADDR;
            wr.write_data = {24'h000000, ch};
            wr.start(m_sequencer);
            `uvm_info("TX_SEQ", $sformatf("AXI Write THR -> char '%c' (0x%02h)", ch, ch), UVM_MEDIUM)
        end
    endtask
endclass : soc_uart_tx_seq

// -----------------------------------------------------------------------------
// Sequence 5: UART VIP Driver transmits serial bytes to DUT uart_rx
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
            item = uart_seq_item::type_id::create("uart_byte_item");
            start_item(item);
            item.payload      = bytes_to_send[i];
            item.baud_divisor = baud_divisor;
            item.parity       = UART_PARITY_NONE;
            item.stop_bits    = UART_STOP_1BIT;
            finish_item(item);
        end
    endtask
endclass : uart_rx_drive_seq

`endif // SOC_SEQUENCES_SV
