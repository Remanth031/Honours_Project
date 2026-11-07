// =============================================================================
// core_monitor.sv – Core-to-UART Direct Bus Monitor
// =============================================================================
`ifndef CORE_MONITOR_SV
`define CORE_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import core_types_pkg::*;

class core_monitor extends uvm_monitor;
    `uvm_component_utils(core_monitor)

    virtual core_if vif;
    uvm_analysis_port #(core_seq_item) item_collected_port;

    function new(string name = "core_monitor", uvm_component parent = null);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual core_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        @(posedge vif.rst_n);
        `uvm_info("CORE_MON", "Core Monitor active", UVM_MEDIUM)

        fork
            collect_writes();
            collect_reads();
        join
    endtask

    virtual task collect_writes();
        core_seq_item item;
        bit [4:0]  waddr;
        bit [31:0] wdata;
        bit [3:0]  wstrb;
        bit        aw_done, w_done;

        forever begin
            aw_done = 1'b0;
            w_done  = 1'b0;

            // Wait until both AW and W handshake have occurred
            while (!(aw_done && w_done)) begin
                @(posedge vif.clk);
                if (vif.awvalid && vif.awready) begin
                    waddr   = vif.awaddr;
                    aw_done = 1'b1;
                end
                if (vif.wvalid && vif.wready) begin
                    wdata   = vif.wdata;
                    wstrb   = vif.wstrb;
                    w_done  = 1'b1;
                end
            end

            // Wait until B handshake occurs (may already be active in same cycle)
            while (!(vif.bvalid && vif.bready)) begin
                @(posedge vif.clk);
            end

            item = core_seq_item::type_id::create("mon_core_wr_item");
            item.op   = CORE_WRITE;
            item.addr = waddr;
            item.data = wdata;
            item.strb = wstrb;
            item.resp = core_resp_e'(vif.bresp);

            `uvm_info("CORE_MON", $sformatf("Observed Core WRITE: %s", item.convert2string()), UVM_HIGH)
            item_collected_port.write(item);
        end
    endtask

    virtual task collect_reads();
        core_seq_item item;
        bit [4:0]  raddr;
        bit [31:0] rdata;
        bit [1:0]  rresp;
        bit        ar_done;

        forever begin
            ar_done = 1'b0;

            // Wait for AR handshake
            while (!ar_done) begin
                @(posedge vif.clk);
                if (vif.arvalid && vif.arready) begin
                    raddr   = vif.araddr;
                    ar_done = 1'b1;
                end
            end

            // Wait for R handshake (may already be active in same cycle)
            while (!(vif.rvalid && vif.rready)) begin
                @(posedge vif.clk);
            end
            rdata = vif.rdata;
            rresp = vif.rresp;

            item = core_seq_item::type_id::create("mon_core_rd_item");
            item.op   = CORE_READ;
            item.addr = raddr;
            item.data = rdata;
            item.resp = core_resp_e'(rresp);

            `uvm_info("CORE_MON", $sformatf("Observed Core READ: %s", item.convert2string()), UVM_HIGH)
            item_collected_port.write(item);
        end
    endtask

endclass : core_monitor

`endif // CORE_MONITOR_SV
