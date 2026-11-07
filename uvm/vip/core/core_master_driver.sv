// =============================================================================
// core_master_driver.sv – Core Master Driver (Direct Read/Write to UART IP)
// =============================================================================
`ifndef CORE_MASTER_DRIVER_SV
`define CORE_MASTER_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import core_types_pkg::*;

class core_master_driver extends uvm_driver #(core_seq_item);
    `uvm_component_utils(core_master_driver)

    virtual core_if vif;

    function new(string name = "core_master_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual core_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        reset_signals();

        @(posedge vif.rst_n);
        @(posedge vif.clk);
        `uvm_info("CORE_DRV", "Core Master Driver active – ready to drive direct UART transactions", UVM_MEDIUM)

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info("CORE_DRV", $sformatf("Driving direct transaction: %s", req.convert2string()), UVM_HIGH)

            if (req.op == CORE_WRITE) begin
                drive_write(req);
            end else begin
                drive_read(req);
            end

            seq_item_port.item_done();
        end
    endtask

    virtual task reset_signals();
        vif.awaddr  <= '0;
        vif.awvalid <= 1'b0;
        vif.wdata   <= '0;
        vif.wstrb   <= '0;
        vif.wvalid  <= 1'b0;
        vif.bready  <= 1'b0;

        vif.araddr  <= '0;
        vif.arvalid <= 1'b0;
        vif.rready  <= 1'b0;
    endtask

    virtual task drive_write(core_seq_item item);
        repeat (item.delay) @(posedge vif.clk);

        @(posedge vif.clk);
        // Assert Write Address and Write Data directly to UART
        vif.awaddr  <= item.addr;
        vif.awvalid <= 1'b1;
        vif.wdata   <= item.data;
        vif.wstrb   <= item.strb;
        vif.wvalid  <= 1'b1;
        vif.bready  <= 1'b1;

        // Wait for AW/W handshake and BVALID response
        wait (vif.awready && vif.wready);
        wait (vif.bvalid);
        item.resp = core_resp_e'(vif.bresp);

        @(posedge vif.clk);
        vif.awvalid <= 1'b0;
        vif.wvalid  <= 1'b0;
        vif.bready  <= 1'b0;
        repeat (2) @(posedge vif.clk);
    endtask

    virtual task drive_read(core_seq_item item);
        repeat (item.delay) @(posedge vif.clk);

        @(posedge vif.clk);
        // Assert Read Address and RREADY directly to UART
        vif.araddr  <= item.addr;
        vif.arvalid <= 1'b1;
        vif.rready  <= 1'b1;

        // Wait for AR handshake and RVALID response
        wait (vif.arready);
        wait (vif.rvalid);
        item.data = vif.rdata;
        item.resp = core_resp_e'(vif.rresp);

        @(posedge vif.clk);
        vif.arvalid <= 1'b0;
        vif.rready  <= 1'b0;
        repeat (2) @(posedge vif.clk);
    endtask

endclass : core_master_driver

`endif // CORE_MASTER_DRIVER_SV
