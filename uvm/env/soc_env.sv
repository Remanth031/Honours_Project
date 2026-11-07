// =============================================================================
// soc_env.sv – Subsystem UVM Environment
// =============================================================================
`ifndef SOC_ENV_SV
`define SOC_ENV_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_vip_pkg::*;
import uart_vip_pkg::*;

class soc_env extends uvm_env;
    `uvm_component_utils(soc_env)

    axi_master_agent m_axi_agent;
    uart_agent       m_uart_agent;
    soc_scoreboard   m_scoreboard;

    function new(string name = "soc_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        m_axi_agent  = axi_master_agent::type_id::create("m_axi_agent", this);
        m_uart_agent = uart_agent::type_id::create("m_uart_agent", this);
        m_scoreboard = soc_scoreboard::type_id::create("m_scoreboard", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect AXI Monitor to Scoreboard
        m_axi_agent.monitor.item_collected_port.connect(m_scoreboard.axi_export);

        // Connect UART Monitor to Scoreboard
        m_uart_agent.monitor.item_collected_port.connect(m_scoreboard.uart_export);
    endfunction

endclass : soc_env

`endif // SOC_ENV_SV
