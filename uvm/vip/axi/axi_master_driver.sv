// =============================================================================
// axi_master_driver.sv – AXI4 Master Driver
// =============================================================================
`ifndef AXI_MASTER_DRIVER_SV
`define AXI_MASTER_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_types_pkg::*;

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
        `uvm_info("AXI_DRV", "AXI Driver out of reset, ready to drive transactions", UVM_MEDIUM)

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info("AXI_DRV", $sformatf("Driving item: %s", req.convert2string()), UVM_HIGH)

            if (req.rw == AXI_WRITE) begin
                drive_write(req);
            end else begin
                drive_read(req);
            end

            seq_item_port.item_done();
        end
    endtask

    virtual task reset_signals();
        vif.awid    <= '0;
        vif.awaddr  <= '0;
        vif.awlen   <= '0;
        vif.awsize  <= '0;
        vif.awburst <= '0;
        vif.awlock  <= '0;
        vif.awcache <= '0;
        vif.awprot  <= '0;
        vif.awqos   <= '0;
        vif.awvalid <= 1'b0;

        vif.wdata   <= '0;
        vif.wstrb   <= '0;
        vif.wlast   <= 1'b0;
        vif.wvalid  <= 1'b0;

        vif.bready  <= 1'b0;

        vif.arid    <= '0;
        vif.araddr  <= '0;
        vif.arlen   <= '0;
        vif.arsize  <= '0;
        vif.arburst <= '0;
        vif.arlock  <= '0;
        vif.arcache <= '0;
        vif.arprot  <= '0;
        vif.arqos   <= '0;
        vif.arvalid <= 1'b0;

        vif.rready  <= 1'b0;
    endtask

    virtual task drive_write(axi_seq_item item);
        repeat (item.addr_delay) @(posedge vif.clk);

        // Drive Address Write Channel
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

        // Drive Write Data Channel
        vif.wdata   <= item.data[0];
        vif.wstrb   <= item.strb[0];
        vif.wlast   <= (item.len == 0) ? 1'b1 : 1'b0;
        vif.wvalid  <= 1'b1;

        fork
            // Wait for AWREADY
            begin
                do @(posedge vif.clk); while (!vif.awready);
                vif.awvalid <= 1'b0;
            end
            // Wait for WREADY
            begin
                do @(posedge vif.clk); while (!vif.wready);
                vif.wvalid <= 1'b0;
                vif.wlast  <= 1'b0;
            end
        join

        // Burst beats (if len > 0)
        for (int b = 1; b <= item.len; b++) begin
            vif.wdata  <= item.data[b];
            vif.wstrb  <= item.strb[b];
            vif.wlast  <= (b == item.len) ? 1'b1 : 1'b0;
            vif.wvalid <= 1'b1;
            do @(posedge vif.clk); while (!vif.wready);
            vif.wvalid <= 1'b0;
            vif.wlast  <= 1'b0;
        end

        // Wait for B Response
        vif.bready <= 1'b1;
        do @(posedge vif.clk); while (!vif.bvalid);
        item.resp[0] = axi_resp_e'(vif.bresp);
        @(posedge vif.clk);
        vif.bready <= 1'b0;
    endtask

    virtual task drive_read(axi_seq_item item);
        repeat (item.addr_delay) @(posedge vif.clk);

        // Drive Address Read Channel
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

        // Read Data Channel
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

`endif // AXI_MASTER_DRIVER_SV
