#!/usr/bin/env bash
# ==============================================================================
# run_vcs.sh – Synopsys VCS Compilation and Simulation Script
#
# Usage:
#   ./run_vcs.sh [engine | soc | all]
#
# Examples:
#   ./run_vcs.sh engine       # Simulates tb_ar_engine.sv (Accelerator tests)
#   ./run_vcs.sh soc          # Simulates tb_ar_soc_top.sv (Full SoC top tests)
#   ./run_vcs.sh gui          # Opens simulation results in Synopsys DVE GUI
# ==============================================================================

set -e

MODE="${1:-engine}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=============================================================================="
echo "               SYNOPSYS VCS SIMULATION & VERIFICATION RUNNER                  "
echo "=============================================================================="

# Setup Synopsys tools if not in PATH
export VCS_HOME=/home/student/snps_tools_target/vcs/U-2023.03
export VERDI_HOME=/home/student/snps_tools_target/verdi/U-2023.03-SP1
export SNPSLMD_LICENSE_FILE=27021@14.139.1.126
export PATH=$VCS_HOME/bin:$VERDI_HOME/bin:$PATH
export RV_ROOT="${SCRIPT_DIR}/Cores-VeeR-EL2"

mkdir -p sim/build sim/waves sim/logs

# Common VCS flags
VCS_FLAGS=(
    -sverilog
    -full64
    -timescale=1ns/1ps
    +v2k
    +define+VCS
    +vcs+dumpvars+sim/waves/tb_ar_engine.vcd
    +vcs+vcdpluson
    -debug_access+all
    -kdb
    -l sim/logs/vcs_compile.log
    +incdir+./include
    +incdir+./rtl/soc
    +incdir+./rtl/accelerator
    +incdir+./rtl/peripherals
    +incdir+./rtl/core
    +incdir+./rtl/interconnect
    +incdir+./tb
    +incdir+./snapshots/default
    +incdir+./Cores-VeeR-EL2/design/include
    +incdir+./Cores-VeeR-EL2/design/lib
    +incdir+./Cores-VeeR-EL2/design/dmi
    +incdir+./uart_ip/axi-lite_uart-ipcore-develop/src/include
)

# Ensure boot_rom.vmem is accessible in working directory
if [ ! -f "boot_rom.vmem" ] && [ -f "rtl/peripherals/boot_rom.vmem" ]; then
    ln -s rtl/peripherals/boot_rom.vmem boot_rom.vmem
fi

if [ "$MODE" == "engine" ]; then
    echo "[INFO] Compiling and running tb_ar_engine (Array Rasterizer Accelerator)..."
    vcs "${VCS_FLAGS[@]}" \
        rtl/accelerator/ar_engine.v \
        tb/tb_ar_engine.sv \
        -o sim/build/simv_engine

    echo "[INFO] Running simulation..."
    ./sim/build/simv_engine -l sim/logs/simv_engine.log

    echo "[INFO] Waveform generated: sim/waves/tb_ar_engine.vcd / vcdplus.vpd"
    echo "[TIP] To view in Verdi GUI, run: verdi -ssf sim/waves/tb_ar_engine.vcd &"

elif [ "$MODE" == "soc" ]; then
    echo "[INFO] Compiling and running tb_ar_soc_top (SoC Top-Level)..."
    vcs "${VCS_FLAGS[@]}" \
        rtl/soc/arbiter.v \
        rtl/soc/priority_encoder.v \
        rtl/soc/reset_ctrl.v \
        rtl/interconnect/axi_interconnect.v \
        rtl/interconnect/axi_interconnect_wrap_4x11.v \
        rtl/peripherals/boot_rom.v \
        rtl/peripherals/data_mem.v \
        rtl/peripherals/framebuffer.v \
        rtl/peripherals/gpio.v \
        rtl/peripherals/hpm.v \
        rtl/peripherals/spi.v \
        rtl/peripherals/timer.v \
        rtl/peripherals/vga_controller.v \
        rtl/peripherals/vga_ctrl_regs.v \
        rtl/accelerator/ar_control.v \
        rtl/accelerator/ar_read_master.v \
        rtl/accelerator/ar_write_master.v \
        rtl/accelerator/ar_engine.v \
        rtl/core/veer_el2_top.sv \
        uart_ip/axi-lite_uart-ipcore-develop/src/rtl/*.v \
        -f Cores-VeeR-EL2/design/flist \
        rtl/soc/ar_soc_top.v \
        tb/tb_ar_soc_top.sv \
        -o sim/build/simv_soc

    echo "[INFO] Running SoC simulation..."
    ./sim/build/simv_soc -l sim/logs/simv_soc.log

    echo "[INFO] Waveform generated: tb_ar_soc_top.vcd"
    echo "[TIP] To view in Verdi GUI, run: verdi -ssf tb_ar_soc_top.vcd &"

elif [ "$MODE" == "gui" ]; then
    if command -v verdi >/dev/null 2>&1; then
        verdi -ssf sim/waves/tb_ar_engine.vcd &
    elif command -v dve >/dev/null 2>&1; then
        dve -vpd vcdplus.vpd &
    fi

elif [ "$MODE" == "all" ]; then
    "$0" engine
    "$0" soc
fi
