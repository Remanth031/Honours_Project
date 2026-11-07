// =============================================================================
// core_uart_env.sv – Direct Core-to-UART UVM Environment
// =============================================================================
`ifndef CORE_UART_ENV_SV
`define CORE_UART_ENV_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import core_types_pkg::*;
import uart_types_pkg::*;
import core_vip_pkg::*;
import uart_vip_pkg::*;

class core_uart_env extends uvm_env;
    `uvm_component_utils(core_uart_env)

    core_master_agent    m_core_agent;
    uart_agent           m_uart_agent;
    core_uart_scoreboard m_scoreboard;

    function new(string name = "core_uart_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        m_core_agent = core_master_agent::type_id::create("m_core_agent", this);
        m_uart_agent = uart_agent::type_id::create("m_uart_agent", this);
        m_scoreboard = core_uart_scoreboard::type_id::create("m_scoreboard", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect Core Monitor to Scoreboard
        m_core_agent.monitor.item_collected_port.connect(m_scoreboard.core_export);

        // Connect UART Monitor to Scoreboard
        m_uart_agent.monitor.item_collected_port.connect(m_scoreboard.uart_export);
    endfunction

endclass : core_uart_env

`endif // CORE_UART_ENV_SV
