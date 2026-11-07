#!/usr/bin/env bash
# ==============================================================================
# run_unified_tb.sh – Single Unified UVM Testbench Runner
#                     (Zero AXI Interconnect, Direct Core-to-UART)
#
# Runs all verification testcases in a SINGLE testbench run and outputs
# passed/failed statistics.
# ==============================================================================

set -e

# Synopsys License & Tools Setup
export SNPSLMD_LICENSE_FILE="27021@14.139.1.126"
export LM_LICENSE_FILE="27021@14.139.1.126"
export VCS_HOME="/home/student/snps_tools_target/vcs/U-2023.03"
export VERDI_HOME="/home/student/snps_tools_target/verdi/U-2023.03-SP1"
export PATH="${VCS_HOME}/bin:${VERDI_HOME}/bin:${PATH}"

UVM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${UVM_DIR}/.." && pwd)"

cd "${UVM_DIR}"

echo "=============================================================================="
echo "    COMPILING UNIFIED DIRECT CORE-TO-UART UVM TESTBENCH (NO AXI INTERCONNECT)"
echo "=============================================================================="

VCS_FLAGS=(
    -sverilog
    -full64
    -timescale=1ns/1ps
    -ntb_opts uvm-1.2
    +v2k
    +define+UVM_NO_DEPRECATED
    -debug_access+all
    -kdb
    -l "${UVM_DIR}/vcs_uvm_compile.log"
    +incdir+"${UVM_DIR}/vip/core"
    +incdir+"${UVM_DIR}/vip/uart"
    +incdir+"${UVM_DIR}/dut"
    +incdir+"${UVM_DIR}/env"
    +incdir+"${UVM_DIR}/seq"
    +incdir+"${UVM_DIR}/tests"
    +incdir+"${UVM_DIR}/tb"
    +incdir+"${ROOT_DIR}/uart_ip/axi-lite_uart-ipcore-develop/src/include"
)

SRC_FILES=(
    # UART IP Core RTL (Pure peripheral, NO interconnect)
    "${ROOT_DIR}/uart_ip/axi-lite_uart-ipcore-develop/src/rtl/axi_internal_fifo.v"
    "${ROOT_DIR}/uart_ip/axi-lite_uart-ipcore-develop/src/rtl/axi_uart_top.v"
    "${ROOT_DIR}/uart_ip/axi-lite_uart-ipcore-develop/src/rtl/uart_controller.v"
    "${ROOT_DIR}/uart_ip/axi-lite_uart-ipcore-develop/src/rtl/uart_parity_bit_compute.v"
    "${ROOT_DIR}/uart_ip/axi-lite_uart-ipcore-develop/src/rtl/uart_receiver.v"
    "${ROOT_DIR}/uart_ip/axi-lite_uart-ipcore-develop/src/rtl/uart_transmitter.v"

    # DUT: Direct Core-to-UART wrapper (no AXI interconnect)
    "${UVM_DIR}/dut/core_uart_direct_top.sv"

    # Core VIP
    "${UVM_DIR}/vip/core/core_types_pkg.sv"
    "${UVM_DIR}/vip/core/core_if.sv"
    "${UVM_DIR}/vip/core/core_vip_pkg.sv"

    # UART Serial VIP
    "${UVM_DIR}/vip/uart/uart_types_pkg.sv"
    "${UVM_DIR}/vip/uart/uart_if.sv"
    "${UVM_DIR}/vip/uart/uart_vip_pkg.sv"

    # Environment & Top
    "${UVM_DIR}/env/core_uart_env_pkg.sv"
    "${UVM_DIR}/tb/tb_core_uart_uvm_top.sv"
)

vcs "${VCS_FLAGS[@]}" "${SRC_FILES[@]}" -o simv_core_uart_uvm

echo "[INFO] Compilation successful! Executable: ${UVM_DIR}/simv_core_uart_uvm"
echo ""
echo "=============================================================================="
echo "    RUNNING SINGLE UNIFIED UVM TESTBENCH: core_uart_unified_test              "
echo "=============================================================================="

./simv_core_uart_uvm +UVM_TESTNAME=core_uart_unified_test +UVM_VERBOSITY=UVM_LOW -l "${UVM_DIR}/simv_unified_test.log"

echo ""
echo "=============================================================================="
echo "    WAVEFORMS RECORDED FOR SYNOPSYS VERDI:                                    "
echo "    File: ${UVM_DIR}/core_uart_uvm.vcd                                        "
echo "    Launch Command:                                                           "
echo "      verdi -ssf ${UVM_DIR}/core_uart_uvm.vcd &                               "
echo "=============================================================================="
