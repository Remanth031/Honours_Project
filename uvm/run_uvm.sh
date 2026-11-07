#!/usr/bin/env bash
# ==============================================================================
# run_uvm.sh – Direct Core-to-UART UVM Compilation & Execution Script
#              (ZERO AXI Interconnect in between)
#
# Usage:
#   ./run_uvm.sh [rw | tx | rx | duplex | all]
# ==============================================================================

set -e

# Setup Synopsys VCS & License Environment
export SNPSLMD_LICENSE_FILE="27021@14.139.1.126"
export LM_LICENSE_FILE="27021@14.139.1.126"
export VCS_HOME="/home/student/snps_tools_target/vcs/U-2023.03"
export VERDI_HOME="/home/student/snps_tools_target/verdi/U-2023.03-SP1"
export PATH="${VCS_HOME}/bin:${VERDI_HOME}/bin:${PATH}"

UVM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${UVM_DIR}/.." && pwd)"

TEST_ARG="${1:-unified}"

echo "=============================================================================="
echo "      UVM DIRECT CORE-TO-UART VERIFICATION (NO AXI INTERCONNECT)              "
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

echo "[INFO] Compiling Direct Core-to-UART UVM Testbench with Synopsys VCS..."
cd "${UVM_DIR}"

vcs "${VCS_FLAGS[@]}" "${SRC_FILES[@]}" -o simv_core_uart_uvm

echo "[INFO] Compilation successful! Generated simv_core_uart_uvm."

run_single_test() {
    local tname="$1"
    echo ""
    echo "------------------------------------------------------------------------------"
    echo " RUNNING TEST: ${tname}"
    echo "------------------------------------------------------------------------------"
    ./simv_core_uart_uvm +UVM_TESTNAME="${tname}" +UVM_VERBOSITY=UVM_LOW -l "${UVM_DIR}/simv_${tname}.log"
}

if [ "$TEST_ARG" == "unified" ]; then
    run_single_test "core_uart_unified_test"
elif [ "$TEST_ARG" == "rw" ]; then
    run_single_test "core_uart_direct_rw_test"
elif [ "$TEST_ARG" == "tx" ]; then
    run_single_test "core_uart_direct_tx_test"
elif [ "$TEST_ARG" == "rx" ]; then
    run_single_test "core_uart_direct_rx_test"
elif [ "$TEST_ARG" == "duplex" ]; then
    run_single_test "core_uart_direct_duplex_test"
elif [ "$TEST_ARG" == "all" ]; then
    echo "[INFO] Executing All Direct Core-to-UART UVM Verification Testcases..."
    run_single_test "core_uart_unified_test"
    run_single_test "core_uart_direct_rw_test"
    run_single_test "core_uart_direct_tx_test"
    run_single_test "core_uart_direct_rx_test"
    run_single_test "core_uart_direct_duplex_test"
    echo ""
    echo "=============================================================================="
    echo "     ALL TESTS PASSED! OPEN WAVEFORMS IN SYNOPSYS VERDI:                      "
    echo "     verdi -ssf core_uart_uvm.vcd &                                           "
    echo "=============================================================================="
fi
