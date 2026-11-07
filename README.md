# RISC-V SoC & Array Rasterizer (AR) Accelerator

This repository contains the complete synthesizable RTL, software, simulation, and UVM verification environment for a 32-bit RISC-V System-on-Chip featuring the Western Digital VeeR EL2 core, an AXI4 interconnect subsystem, on-chip peripherals, and a dedicated 2D hardware graphics acceleration engine (Array Rasterizer).

---

## Repository Structure

```
.
├── rtl/                        # Synthesizable RTL source files
│   ├── soc/                    # SoC Top-level, arbitration, reset & priority logic
│   │   ├── ar_soc_top.v        # Main SoC top-level module
│   │   ├── arbiter.v           # Multi-master round-robin bus arbiter
│   │   ├── priority_encoder.v  # Priority encoder logic
│   │   └── reset_ctrl.v        # System reset controller & synchronizer
│   ├── accelerator/            # Array Rasterizer (AR) Graphics Engine
│   │   ├── ar_engine.v         # Bresenham rasterizer core
│   │   ├── ar_control.v        # Control registers & FSM
│   │   ├── ar_read_master.v    # DMA vertex/primitive read master
│   │   └── ar_write_master.v   # Framebuffer pixel write master
│   ├── interconnect/           # AXI4 Interconnect crossbars & wrappers
│   │   ├── axi_interconnect.v
│   │   ├── axi_interconnect_wrap_4x11.v
│   │   ├── axi_interconnect_wrap_4x5.v
│   │   └── axi_interconnect_wrap_4x6.v
│   ├── peripherals/            # On-chip peripherals & memory blocks
│   │   ├── boot_rom.v          # AXI4 Boot ROM (4 KB)
│   │   ├── boot_rom.vmem       # Boot ROM firmware image
│   │   ├── data_mem.v          # On-chip SRAM Data Memory (16 MB)
│   │   ├── framebuffer.v       # 2D Display Framebuffer memory
│   │   ├── gpio.v              # General Purpose I/O controller
│   │   ├── hpm.v               # Hardware Performance Monitor
│   │   ├── spi.v               # SPI Master interface controller
│   │   ├── timer.v             # Real-time counter and system timer
│   │   ├── vga_controller.v    # 640x480 VGA display controller
│   │   └── vga_ctrl_regs.v     # VGA control and resolution registers
│   └── core/                   # CPU Core Wrappers
│       ├── veer_el2_top.sv     # Full Western Digital VeeR EL2 RV32IMC CPU wrapper
│       └── veer_el2_stub.v     # Bus functional fallback CPU stub
├── include/                    # Hardware register definitions & C headers
│   ├── ar.h                    # Array Rasterizer register map
│   ├── gpio.h                  # GPIO register definitions
│   ├── reset_ctrl.h            # Reset controller register definitions
│   ├── spi.h                   # SPI register definitions
│   ├── timer.h                 # Timer register definitions
│   ├── uart.h                  # UART register definitions
│   └── vga.h                   # VGA controller register definitions
├── sw/                         # Software, Firmware & Bare-metal test programs
│   ├── bsp/                    # Board support package
│   │   ├── startup.S           # RISC-V CRT0 startup assembly
│   │   └── link.ld             # Linker script (Boot ROM @ 0x3000_0000)
│   ├── hello/                  # "Hello World" diagnostic firmware
│   │   ├── hello.c
│   │   ├── hello.elf
│   │   ├── hello.bin
│   │   ├── hello.hex
│   │   └── hello.vmem
│   └── uart_test/              # UART diagnostic firmware
│       ├── uart_test.c
│       ├── uart_test.elf
│       ├── uart_test.bin
│       ├── uart_test.hex
│       └── uart_test.vmem
├── tb/                         # Directed SystemVerilog testbenches & C++ golden models
│   ├── tb_ar_soc_top.sv        # Full SoC Top-level SystemVerilog testbench
│   ├── tb_ar_engine.sv         # Self-checking Bresenham rasterizer testbench
│   ├── axi_uart_vip.sv         # Standalone AXI-UART VIP
│   └── cpp/                    # Golden reference C++ software models
│       ├── test_bresenham.cpp  # Mathematical Bresenham reference model
│       ├── verify_ar_engine.cpp# >100 automated corner-case verification testbench
│       └── verify_results.txt  # Golden reference verification log
├── uvm/                        # UVM 1.2 Verification Environment (Direct Core <-> UART)
│   ├── dut/                    # Direct Core-to-UART DUT subsystem (Zero Interconnect)
│   ├── vip/                    # Verification IPs (Core Master VIP, UART Serial VIP, AXI VIP)
│   ├── env/                    # UVM Scoreboard and Environment packages
│   ├── seq/                    # Direct Read/Write and Serial sequences
│   ├── tests/                  # UVM testcases including Unified Single TB test
│   ├── tb/                     # Top-level UVM testbench module
│   ├── run_unified_tb.sh       # Unified single UVM testbench runner
│   └── run_uvm.sh              # Multi-mode UVM verification runner
├── scripts/                    # Python and utility automation scripts
│   ├── run_vcs.sh              # Synopsys VCS compilation and simulation runner
│   └── axi_interconnect_wrap.py# AXI crossbar wrapper generator
├── docs/                       # Specifications & architecture documentation
│   ├── Array_Rasterizer_Accelerator_Abstract_Architecture.pdf
│   └── axi-lite_uart-ipcore-develop.zip
├── sim/                        # Simulation build files, waveforms & logs (Git-ignored)
│   ├── build/                  # Compiled simv binaries and daidir databases
│   ├── waves/                  # Dumped VCD and VPD waveform traces
│   └── logs/                   # VCS compilation and simulation runtime logs
├── Cores-VeeR-EL2/             # Western Digital VeeR EL2 RISC-V Core Submodule
├── snapshots/                  # VeeR EL2 Core Configuration Snapshot
├── .gitignore                  # Git ignore rules for simulation & binary artifacts
└── run_vcs.sh                  # Root-level VCS execution shortcut
```

---

## Quick Start & Simulation Commands

### 1. Unified UVM Testbench (Direct Core $\leftrightarrow$ UART, No Interconnect)
Runs all 9 verification testcases (Register Read/Write, TX, RX, Full Duplex, and Data Pattern Sweeps) in a single UVM testbench run:

```bash
cd uvm
./run_unified_tb.sh
```

To plot UVM waveforms in **Synopsys Verdi**:
```bash
cd uvm
verdi -ssf core_uart_uvm.vcd &
```

---

### 2. Array Rasterizer Accelerator Unit Simulation
Simulates the Bresenham rasterizer engine (`ar_engine`) with 10 self-checking testcases:

```bash
./run_vcs.sh engine
```

To plot accelerator waveforms in **Synopsys Verdi**:
```bash
verdi -ssf sim/waves/tb_ar_engine.vcd &
```

---

### 3. Full SoC Top-Level Simulation
Simulates the complete SoC (`ar_soc_top`) integrating VeeR EL2 CPU, AXI Interconnect, Graphics Accelerator, Boot ROM, Framebuffer, and all peripherals:

```bash
./run_vcs.sh soc
```

To plot SoC waveforms in **Synopsys Verdi**:
```bash
verdi -ssf tb_ar_soc_top.vcd &
```
