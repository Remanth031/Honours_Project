// =============================================================================
// File: axi_uart_vip.sv
// Project: Array Rasterizer RISC-V SoC
// Description: Comprehensive Consolidated Verification IP (VIP) Package
//              Contains both:
//                1. AXI4 / AXI4-Lite Master VIP (Interface, Types, Item, Driver, Monitor, Sequencer, Agent)
//                2. UART Serial VIP (Interface, Types, Item, Driver, Monitor, Sequencer, Agent)
// =============================================================================

`ifndef AXI_UART_VIP_SV
`define AXI_UART_VIP_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

// =============================================================================
// SECTION 1: AXI4 MASTER VIP
// =============================================================================

// -----------------------------------------------------------------------------
// 1.1 AXI4 Interface
// -----------------------------------------------------------------------------
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

    modport master  (clocking drv_cb, input clk, rst_n);
    modport monitor (clocking mon_cb, input clk, rst_n);
endinterface : axi_if


// -----------------------------------------------------------------------------
// 1.2 AXI VIP Package
// -----------------------------------------------------------------------------
package axi_vip_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Types & Enums
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

    // Sequence Item
    class axi_seq_item extends uvm_sequence_item;
        rand bit [31:0]         addr;
        rand bit [31:0]         data[];
        rand bit [3:0]          strb[];
        rand axi_rw_e           rw;
        rand bit [7:0]          id;
        rand bit [7:0]          len;       // 0 = 1 beat
        rand axi_size_e         size;
        rand axi_burst_e        burst;
        rand int unsigned       addr_delay;
        rand int unsigned       data_delay;

        axi_resp_e              resp[];

        constraint c_len        { len inside {[0:15]}; }
        constraint c_size       { size == AXI_SIZE_4_BYTES; }
        constraint c_burst      { burst == AXI_BURST_INCR; }
        constraint c_addr_align { addr[1:0] == 2'b00; }
        constraint c_data_size  { data.size() == (len + 1); strb.size() == (len + 1); }
        constraint c_delays     { addr_delay inside {[0:4]}; data_delay inside {[0:4]}; }

        `uvm_object_utils_begin(axi_seq_item)
            `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
            `uvm_field_array_int(data, UVM_ALL_ON | UVM_HEX)
            `uvm_field_array_int(strb, UVM_ALL_ON | UVM_BIN)
            `uvm_field_enum(axi_rw_e, rw, UVM_ALL_ON)
            `uvm_field_int(id, UVM_ALL_ON)
            `uvm_field_int(len, UVM_ALL_ON | UVM_DEC)
            `uvm_field_enum(axi_size_e, size, UVM_ALL_ON)
            `uvm_field_enum(axi_burst_e, burst, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "axi_seq_item");
            super.new(name);
            data = new[1];
            strb = new[1]; strb[0] = 4'b1111;
            resp = new[1]; resp[0] = AXI_RESP_OKAY;
            rw = AXI_WRITE;
            len = 0;
            size = AXI_SIZE_4_BYTES;
            burst = AXI_BURST_INCR;
        endfunction

        virtual function string convert2string();
            string s;
            s = $sformatf("AXI_TR [%s] ID=0x%0h ADDR=0x%08h LEN=%0d DATA=[",
                          (rw == AXI_WRITE) ? "WRITE" : "READ", id, addr, len);
            for (int i = 0; i < data.size(); i++) begin
                s = {s, $sformatf(" 0x%08h", data[i])};
            end
            s = {s, $sformatf(" ] RESP=%s", (resp.size() > 0) ? resp[0].name() : "NONE")};
            return s;
        endfunction
    endclass : axi_seq_item

    // Sequencer
    class axi_sequencer extends uvm_sequencer #(axi_seq_item);
        `uvm_component_utils(axi_sequencer)
        function new(string name = "axi_sequencer", uvm_component parent = null);
            super.new(name, parent);
        endfunction
    endclass : axi_sequencer

    // Driver
    class axi_master_driver extends uvm_driver #(axi_seq_item);
        `uvm_component_utils(axi_master_driver)
        virtual axi_if vif;

        function new(string name = "axi_master_driver", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
            end
        endfunction

        virtual task run_phase(uvm_phase phase);
            reset_signals();
            @(posedge vif.rst_n);
            @(posedge vif.clk);
            forever begin
                seq_item_port.get_next_item(req);
                if (req.rw == AXI_WRITE) drive_write(req);
                else                     drive_read(req);
                seq_item_port.item_done();
            end
        endtask

        virtual task reset_signals();
            vif.awid <= '0; vif.awaddr <= '0; vif.awlen <= '0; vif.awsize <= '0;
            vif.awburst <= '0; vif.awlock <= '0; vif.awcache <= '0; vif.awprot <= '0;
            vif.awqos <= '0; vif.awvalid <= 1'b0;
            vif.wdata <= '0; vif.wstrb <= '0; vif.wlast <= 1'b0; vif.wvalid <= 1'b0;
            vif.bready <= 1'b0;
            vif.arid <= '0; vif.araddr <= '0; vif.arlen <= '0; vif.arsize <= '0;
            vif.arburst <= '0; vif.arlock <= '0; vif.arcache <= '0; vif.arprot <= '0;
            vif.arqos <= '0; vif.arvalid <= 1'b0;
            vif.rready <= 1'b0;
        endtask

        virtual task drive_write(axi_seq_item item);
            repeat (item.addr_delay) @(posedge vif.clk);
            vif.awid    <= item.id;
            vif.awaddr  <= item.addr;
            vif.awlen   <= item.len;
            vif.awsize  <= item.size;
            vif.awburst <= item.burst;
            vif.awlock  <= 1'b0;
            vif.awcache <= 4'b0011;
            vif.awprot  <= 3'b000;
            vif.awqos   <= 4'b0000;
            vif.awvalid <= 1'b1;

            vif.wdata   <= item.data[0];
            vif.wstrb   <= item.strb[0];
            vif.wlast   <= (item.len == 0) ? 1'b1 : 1'b0;
            vif.wvalid  <= 1'b1;

            fork
                begin do @(posedge vif.clk); while (!vif.awready); vif.awvalid <= 1'b0; end
                begin do @(posedge vif.clk); while (!vif.wready);  vif.wvalid <= 1'b0; vif.wlast <= 1'b0; end
            join

            for (int b = 1; b <= item.len; b++) begin
                vif.wdata  <= item.data[b];
                vif.wstrb  <= item.strb[b];
                vif.wlast  <= (b == item.len) ? 1'b1 : 1'b0;
                vif.wvalid <= 1'b1;
                do @(posedge vif.clk); while (!vif.wready);
                vif.wvalid <= 1'b0;
                vif.wlast  <= 1'b0;
            end

            vif.bready <= 1'b1;
            do @(posedge vif.clk); while (!vif.bvalid);
            item.resp[0] = axi_resp_e'(vif.bresp);
            @(posedge vif.clk);
            vif.bready <= 1'b0;
        endtask

        virtual task drive_read(axi_seq_item item);
            repeat (item.addr_delay) @(posedge vif.clk);
            vif.arid    <= item.id;
            vif.araddr  <= item.addr;
            vif.arlen   <= item.len;
            vif.arsize  <= item.size;
            vif.arburst <= item.burst;
            vif.arlock  <= 1'b0;
            vif.arcache <= 4'b0011;
            vif.arprot  <= 3'b000;
            vif.arqos   <= 4'b0000;
            vif.arvalid <= 1'b1;

            do @(posedge vif.clk); while (!vif.arready);
            vif.arvalid <= 1'b0;

            vif.rready <= 1'b1;
            item.data = new[item.len + 1];
            item.resp = new[item.len + 1];

            for (int b = 0; b <= item.len; b++) begin
                do @(posedge vif.clk); while (!vif.rvalid);
                item.data[b] = vif.rdata;
                item.resp[b] = axi_resp_e'(vif.rresp);
            end
            @(posedge vif.clk);
            vif.rready <= 1'b0;
        endtask
    endclass : axi_master_driver

    // Monitor
    class axi_monitor extends uvm_monitor;
        `uvm_component_utils(axi_monitor)
        virtual axi_if vif;
        uvm_analysis_port #(axi_seq_item) item_collected_port;

        function new(string name = "axi_monitor", uvm_component parent = null);
            super.new(name, parent);
            item_collected_port = new("item_collected_port", this);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
            end
        endfunction

        virtual task run_phase(uvm_phase phase);
            @(posedge vif.rst_n);
            fork
                collect_writes();
                collect_reads();
            join
        endtask

        virtual task collect_writes();
            axi_seq_item item;
            bit [31:0] waddr; bit [7:0] wid; bit [7:0] wlen;
            forever begin
                do @(posedge vif.clk); while (!(vif.awvalid && vif.awready));
                waddr = vif.awaddr; wid = vif.awid; wlen = vif.awlen;

                item = axi_seq_item::type_id::create("mon_write_item");
                item.rw = AXI_WRITE; item.addr = waddr; item.id = wid; item.len = wlen;
                item.data = new[wlen + 1]; item.strb = new[wlen + 1]; item.resp = new[1];

                for (int b = 0; b <= wlen; b++) begin
                    do @(posedge vif.clk); while (!(vif.wvalid && vif.wready));
                    item.data[b] = vif.wdata; item.strb[b] = vif.wstrb;
                end

                do @(posedge vif.clk); while (!(vif.bvalid && vif.bready));
                item.resp[0] = axi_resp_e'(vif.bresp);
                item_collected_port.write(item);
            end
        endtask

        virtual task collect_reads();
            axi_seq_item item;
            forever begin
                do @(posedge vif.clk); while (!(vif.arvalid && vif.arready));
                item = axi_seq_item::type_id::create("mon_read_item");
                item.rw = AXI_READ; item.addr = vif.araddr; item.id = vif.arid; item.len = vif.arlen;
                item.data = new[item.len + 1]; item.resp = new[item.len + 1];

                for (int b = 0; b <= item.len; b++) begin
                    do @(posedge vif.clk); while (!(vif.rvalid && vif.rready));
                    item.data[b] = vif.rdata; item.resp[b] = axi_resp_e'(vif.rresp);
                end
                item_collected_port.write(item);
            end
        endtask
    endclass : axi_monitor

    // Agent
    class axi_master_agent extends uvm_agent;
        `uvm_component_utils(axi_master_agent)
        axi_sequencer     sequencer;
        axi_master_driver driver;
        axi_monitor       monitor;

        function new(string name = "axi_master_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = axi_monitor::type_id::create("monitor", this);
            if (get_is_active() == UVM_ACTIVE) begin
                sequencer = axi_sequencer::type_id::create("sequencer", this);
                driver    = axi_master_driver::type_id::create("driver", this);
            end
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE) begin
                driver.seq_item_port.connect(sequencer.seq_item_export);
            end
        endfunction
    endclass : axi_master_agent

endpackage : axi_vip_pkg


// =============================================================================
// SECTION 2: UART SERIAL VIP
// =============================================================================

// -----------------------------------------------------------------------------
// 2.1 UART Interface
// -----------------------------------------------------------------------------
interface uart_if(
    input logic clk,
    input logic rst_n
);
    logic uart_rx; // Driven into DUT
    logic uart_tx; // Monitored from DUT
    logic uart_irq;// Interrupt line from DUT

    modport dut (input uart_rx, output uart_tx, output uart_irq);
    modport tb  (output uart_rx, input uart_tx, input uart_irq);
endinterface : uart_if


// -----------------------------------------------------------------------------
// 2.2 UART VIP Package
// -----------------------------------------------------------------------------
package uart_vip_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    typedef enum bit [1:0] {
        UART_PARITY_NONE = 2'b00,
        UART_PARITY_ODD  = 2'b01,
        UART_PARITY_EVEN = 2'b10
    } uart_parity_e;

    typedef enum bit {
        UART_STOP_1BIT = 1'b0,
        UART_STOP_2BIT = 1'b1
    } uart_stop_e;

    // Sequence Item
    class uart_seq_item extends uvm_sequence_item;
        rand bit [7:0]          payload;
        rand uart_parity_e      parity;
        rand uart_stop_e        stop_bits;
        rand int unsigned       baud_divisor;
        rand bit                inject_parity_err;
        rand bit                inject_frame_err;

        constraint c_baud   { baud_divisor inside {[4:64]}; }
        constraint c_parity { parity == UART_PARITY_NONE; }
        constraint c_stop   { stop_bits == UART_STOP_1BIT; }
        constraint c_err    { inject_parity_err == 1'b0; inject_frame_err == 1'b0; }

        `uvm_object_utils_begin(uart_seq_item)
            `uvm_field_int(payload, UVM_ALL_ON | UVM_HEX)
            `uvm_field_enum(uart_parity_e, parity, UVM_ALL_ON)
            `uvm_field_enum(uart_stop_e, stop_bits, UVM_ALL_ON)
            `uvm_field_int(baud_divisor, UVM_ALL_ON | UVM_DEC)
        `uvm_object_utils_end

        function new(string name = "uart_seq_item");
            super.new(name);
            payload = 8'h00; parity = UART_PARITY_NONE; stop_bits = UART_STOP_1BIT;
            baud_divisor = 16; inject_parity_err = 0; inject_frame_err = 0;
        endfunction

        virtual function string convert2string();
            return $sformatf("UART_ITEM: DATA=0x%02h ('%c') PARITY=%s STOP=%s BAUD_DIV=%0d",
                             payload, (payload >= 32 && payload <= 126) ? payload : ".",
                             parity.name(), stop_bits.name(), baud_divisor);
        endfunction
    endclass : uart_seq_item

    // Sequencer
    class uart_sequencer extends uvm_sequencer #(uart_seq_item);
        `uvm_component_utils(uart_sequencer)
        function new(string name = "uart_sequencer", uvm_component parent = null);
            super.new(name, parent);
        endfunction
    endclass : uart_sequencer

    // Driver
    class uart_driver extends uvm_driver #(uart_seq_item);
        `uvm_component_utils(uart_driver)
        virtual uart_if vif;

        function new(string name = "uart_driver", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
            end
        endfunction

        virtual task run_phase(uvm_phase phase);
            vif.uart_rx <= 1'b1; // Idle line is HIGH
            @(posedge vif.rst_n);
            forever begin
                seq_item_port.get_next_item(req);
                transmit_byte(req);
                seq_item_port.item_done();
            end
        endtask

        virtual task transmit_byte(uart_seq_item item);
            int baud_cycles;
            bit parity_calc;

            baud_cycles = item.baud_divisor + 1;

            // Start Bit (Low)
            vif.uart_rx <= 1'b0;
            repeat (baud_cycles) @(posedge vif.clk);

            // 8 Data Bits
            for (int i = 0; i < 8; i++) begin
                vif.uart_rx <= item.payload[i];
                repeat (baud_cycles) @(posedge vif.clk);
            end

            // Parity Bit
            if (item.parity != UART_PARITY_NONE) begin
                parity_calc = ^item.payload;
                if (item.parity == UART_PARITY_ODD) parity_calc = ~parity_calc;
                if (item.inject_parity_err) parity_calc = ~parity_calc;
                vif.uart_rx <= parity_calc;
                repeat (baud_cycles) @(posedge vif.clk);
            end

            // Stop Bit
            vif.uart_rx <= item.inject_frame_err ? 1'b0 : 1'b1;
            repeat (baud_cycles) @(posedge vif.clk);

            if (item.stop_bits == UART_STOP_2BIT) begin
                vif.uart_rx <= 1'b1;
                repeat (baud_cycles) @(posedge vif.clk);
            end

            // Inter-character idle delay
            vif.uart_rx <= 1'b1;
            repeat (baud_cycles) @(posedge vif.clk);
        endtask
    endclass : uart_driver

    // Monitor
    class uart_monitor extends uvm_monitor;
        `uvm_component_utils(uart_monitor)
        virtual uart_if vif;
        uvm_analysis_port #(uart_seq_item) item_collected_port;
        int unsigned current_baud_div = 16;

        function new(string name = "uart_monitor", uvm_component parent = null);
            super.new(name, parent);
            item_collected_port = new("item_collected_port", this);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
            end
            void'(uvm_config_db#(int unsigned)::get(this, "", "baud_divisor", current_baud_div));
        endfunction

        virtual task run_phase(uvm_phase phase);
            uart_seq_item item;
            int baud_cycles;

            @(posedge vif.rst_n);
            forever begin
                baud_cycles = current_baud_div + 1;

                // Detect Start Bit falling edge
                @(negedge vif.uart_tx);
                repeat (baud_cycles / 2) @(posedge vif.clk);
                if (vif.uart_tx !== 1'b0) continue;

                item = uart_seq_item::type_id::create("mon_uart_item");
                item.baud_divisor = current_baud_div;

                // Sample 8 data bits
                for (int i = 0; i < 8; i++) begin
                    repeat (baud_cycles) @(posedge vif.clk);
                    item.payload[i] = vif.uart_tx;
                end

                // Sample Stop Bit
                repeat (baud_cycles) @(posedge vif.clk);
                if (vif.uart_tx !== 1'b1) begin
                    `uvm_error("UART_MON", $sformatf("Framing error: Stop bit not HIGH (got %b)", vif.uart_tx))
                end

                item_collected_port.write(item);
            end
        endtask

        function void set_baud_divisor(int unsigned div);
            current_baud_div = div;
        endfunction
    endclass : uart_monitor

    // Agent
    class uart_agent extends uvm_agent;
        `uvm_component_utils(uart_agent)
        uart_sequencer sequencer;
        uart_driver    driver;
        uart_monitor   monitor;

        function new(string name = "uart_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = uart_monitor::type_id::create("monitor", this);
            if (get_is_active() == UVM_ACTIVE) begin
                sequencer = uart_sequencer::type_id::create("sequencer", this);
                driver    = uart_driver::type_id::create("driver", this);
            end
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE) begin
                driver.seq_item_port.connect(sequencer.seq_item_export);
            end
        endfunction
    endclass : uart_agent

endpackage : uart_vip_pkg

`endif // AXI_UART_VIP_SV
