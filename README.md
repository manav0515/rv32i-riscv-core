# RV32I RISC-V Core — RTL-to-GDSII ASIC Implementation

A 5-stage pipelined RV32I RISC-V core written in synthesizable SystemVerilog,
carried through a complete academic ASIC implementation flow — synthesis,
place-and-route, and static timing signoff — on the SAED32nm educational PDK
using the Synopsys toolchain.

## Overview

| | |
|---|---|
| **ISA** | RV32I base integer instruction set |
| **Pipeline** | 5-stage: IF → ID → EX → MEM → WB |
| **Language** | SystemVerilog-2017 |
| **Target frequency** | 100 MHz (10.0 ns period) |
| **Technology** | SAED32nm, RVT standard cell library |
| **Tools** | Synopsys Design Compiler, IC Compiler II, PrimeTime, VCS |

## Features

- Full RV32I base ISA: arithmetic/logical, shifts, immediates, loads/stores,
  conditional branches, JAL/JALR, LUI/AUIPC
- Classic 5-stage pipeline with dedicated pipeline register modules
  (`if_id_reg`, `id_ex_reg`, `ex_mem_reg`, `mem_wb_reg`) to keep timing
  paths short and synthesis-friendly
- **Hazard Detection Unit** — stalls on load-use hazards
- **Forwarding Unit** — EX/MEM → EX and MEM/WB → EX forwarding paths
- Static predict-not-taken branching, resolved in EX, synchronous pipeline
  flush on taken branches/jumps
- Synchronous, active-low reset (`rst_ni`) throughout, single clock (`clk_i`)
- Harvard-style memory interface: single-cycle, zero-wait-state IMEM/DMEM
  ports exposed directly at the top level

**Out of scope** (by design, for a clean academic core): M/A/F/D/C
extensions, CSR instructions, ECALL/EBREAK, interrupts, exceptions, and
virtual memory.

## Repository Structure

```
rv32i-riscv-core/
├── rtl/                # SystemVerilog source (14 modules)
├── verif/              # VCS testbench + behavioral reference model
├── constraints/         # core.sdc
├── synth/               # Design Compiler script (dc.tcl)
├── backend/icc2/         # IC Compiler II flow (01-08)
├── signoff/              # Standalone PrimeTime STA script (09)
├── dft/                  # Scan insertion + TetraMAX ATPG (in progress)
└── docs/                 # Microarchitecture notes, QoR/timing reports
```

## Verification

The design is verified in Synopsys VCS against a lightweight, purely
behavioral RV32I reference model that executes the same instruction image
in true architectural program order. At every genuine write-back
retirement, the DUT's committed register write is checked against the
reference model's output, in addition to a static, per-instruction
expected-value table for a directed test program covering every supported
instruction class, load/store width, taken/not-taken branches, and
back-to-back RAW/load-use hazards.

```bash
cd verif
vcs -sverilog -full64 ../rtl/*.sv rv32i_ref_model.sv tb_core.sv -o simv
./simv
```

## Physical Design Flow

```
RTL (SystemVerilog)
   │  Design Compiler
   ▼
Gate-level netlist + SDC
   │  IC Compiler II
   │  floorplan → power plan → placement → CTS → routing
   ▼
Routed GDS / DEF / SPEF
   │  standalone PrimeTime
   ▼
Signoff STA report
```

```bash
# Synthesis
dc_shell -f synth/dc.tcl

# Place & route (run in numbered order)
icc2_shell -f backend/icc2/01_setup.tcl
icc2_shell -f backend/icc2/02_netlist_read.tcl
...
icc2_shell -f backend/icc2/08_signoff_outputs.tcl

# Standalone signoff STA
pt_shell -f signoff/09_primetime_signoff.tcl
```

All scripts declare PDK/tool paths as Tcl variables in a shared setup
script rather than hardcoding them per-stage — update those once to point
at your own PDK install.

## Status

- [x] RTL (14 modules, fully parameterized control-signal bundling)
- [x] VCS testbench + behavioral reference model
- [x] SDC constraints (100 MHz)
- [x] Design Compiler synthesis script
- [x] IC Compiler II flow, floorplan through signoff outputs
- [x] Standalone PrimeTime signoff script
- [ ] DFT: scan insertion + TetraMAX ATPG *(in progress)*

## License

This project is released under the [MIT License](LICENSE).

## Acknowledgments

Built as part of an academic ASIC physical design course using the
SAED32nm educational PDK. This repository does not redistribute any PDK
files (`.db`, `.ndm`, `.tf`, `.tluplus`, or derived GDS/netlists) — only
the original RTL and Tcl scripts, per standard foundry PDK licensing terms.
