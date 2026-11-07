// =============================================================================
// axi_monitor.sv – AXI4 Bus Monitor
// =============================================================================
`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_types_pkg::*;

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
        `uvm_info("AXI_MON", "AXI Monitor active", UVM_MEDIUM)

        fork
            collect_writes();
            collect_reads();
        join
    endtask

    virtual task collect_writes();
        axi_seq_item item;
        bit [31:0] waddr;
        bit [7:0] wid;
        bit [7:0] wlen;

        forever begin
            // Wait for Address Write handshake
            do @(posedge vif.clk); while (!(vif.awvalid && vif.awready));
            waddr = vif.awaddr;
            wid   = vif.awid;
            wlen  = vif.awlen;

            item = axi_seq_item::type_id::create("mon_write_item");
            item.rw   = AXI_WRITE;
            item.addr = waddr;
            item.id   = wid;
            item.len  = wlen;
            item.data = new[wlen + 1];
            item.strb = new[wlen + 1];
            item.resp = new[1];

            // Collect Write Data beats
            for (int b = 0; b <= wlen; b++) begin
                do @(posedge vif.clk); while (!(vif.wvalid && vif.wready));
                item.data[b] = vif.wdata;
                item.strb[b] = vif.wstrb;
            end

            // Wait for B handshake
            do @(posedge vif.clk); while (!(vif.bvalid && vif.bready));
            item.resp[0] = axi_resp_e'(vif.bresp);

            `uvm_info("AXI_MON", $sformatf("Observed WRITE: %s", item.convert2string()), UVM_HIGH)
            item_collected_port.write(item);
        end
    endtask

    virtual task collect_reads();
        axi_seq_item item;

        forever begin
            // Wait for Address Read handshake
            do @(posedge vif.clk); while (!(vif.arvalid && vif.arready));

            item = axi_seq_item::type_id::create("mon_read_item");
            item.rw   = AXI_READ;
            item.addr = vif.araddr;
            item.id   = vif.arid;
            item.len  = vif.arlen;
            item.data = new[item.len + 1];
            item.resp = new[item.len + 1];

            // Collect Read Data beats
            for (int b = 0; b <= item.len; b++) begin
                do @(posedge vif.clk); while (!(vif.rvalid && vif.rready));
                item.data[b] = vif.rdata;
                item.resp[b] = axi_resp_e'(vif.rresp);
            end

            `uvm_info("AXI_MON", $sformatf("Observed READ: %s", item.convert2string()), UVM_HIGH)
            item_collected_port.write(item);
        end
    endtask

endclass : axi_monitor

`endif // AXI_MONITOR_SV
