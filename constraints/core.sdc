# ============================================================================
# core.sdc
#
# Timing constraints for the RV32I 5-stage pipelined core (top module: core).
# Styled after a classic fifo_sync.sdc structure: clock -> uncertainty ->
# environment (drive/load) -> I/O delays -> design rule constraints.
#
# Target: 100 MHz (10.000 ns period), within the 100-125 MHz project band.
# PDK: SAED32nm educational RVT (saed32rvt_ss0p7vn40c.db)
# ============================================================================

# ----------------------------------------------------------------------
# 1. Design-level variables
# ----------------------------------------------------------------------
set CLK_PORT      clk_i
set CLK_NAME      clk_i
set CLK_PERIOD    10.000
set CLK_UNCERTAINTY_SETUP  0.150
set CLK_UNCERTAINTY_HOLD   0.080
set CLK_TRANSITION         0.100

# I/O delays expressed as a fraction of the clock period, per project spec
# (no false-path exceptions on the IMEM/DMEM interface -- matches the
# single-cycle, zero-wait-state memory assumption).
set INPUT_DELAY_PCT   0.3
set OUTPUT_DELAY_PCT  0.3
set INPUT_DELAY       [expr {$CLK_PERIOD * $INPUT_DELAY_PCT}]
set OUTPUT_DELAY      [expr {$CLK_PERIOD * $OUTPUT_DELAY_PCT}]

# Verify these exact cell names against your target library
# (e.g. `list_lib -cells [get_libs saed32rvt_ss0p7vn40c]` in DC).
set DRIVE_CELL_LIB    saed32rvt_ss0p7vn40c
set DRIVE_CELL        BUFX4_RVT
set DRIVE_CELL_PIN    Z
set LOAD_CELL         INVX1_RVT
set LOAD_CELL_PIN     A

# ----------------------------------------------------------------------
# 2. Clock definition
# ----------------------------------------------------------------------
create_clock -name $CLK_NAME -period $CLK_PERIOD \
    -waveform [list 0 [expr {$CLK_PERIOD / 2.0}]] \
    [get_ports $CLK_PORT]

set_clock_uncertainty -setup $CLK_UNCERTAINTY_SETUP [get_clocks $CLK_NAME]
set_clock_uncertainty -hold  $CLK_UNCERTAINTY_HOLD  [get_clocks $CLK_NAME]
set_clock_transition  $CLK_TRANSITION [get_clocks $CLK_NAME]

# FOUNDRY DELTA
# In DC, the clock above is treated as IDEAL (zero insertion delay, zero
# skew) prior to CTS. A real commercial tapeout flow would additionally
# specify early/late clock latency ranges (set_clock_latency -early/-late,
# or estimated pre-CTS latency via set_clock_tree_options) and would run
# full advanced-on-chip-variation (AOCV/POCV) derating rather than the
# flat clock_uncertainty margin used here. Post-CTS (ICC2 step 06), the
# clock becomes a real propagated network and clock_opt manages skew
# directly, superseding this ideal-network assumption. This academic flow
# uses a single flat uncertainty margin as a simplified stand-in.

# ----------------------------------------------------------------------
# 3. Reset
#
# rst_ni is an ACTIVE-LOW SYNCHRONOUS reset (per project spec), sampled by
# clk_i like any other data input. It is therefore timed with a normal
# set_input_delay below and is deliberately NOT given set_false_path or
# an ideal/exclude-from-timing treatment, unlike the asynchronous-reset
# handling typical of a stock fifo_sync.sdc reference. Treating it as a
# real timed path is required so DC/ICC2 correctly close setup/hold on
# whatever reset-fanout logic exists in the design.
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# 4. Environment: default driving cell / output load on boundary I/O
# ----------------------------------------------------------------------
set_driving_cell -lib_cell $DRIVE_CELL -pin $DRIVE_CELL_PIN \
    -library $DRIVE_CELL_LIB \
    [remove_from_collection [all_inputs] [get_ports $CLK_PORT]]

set_load [load_of ${DRIVE_CELL_LIB}/${LOAD_CELL}/${LOAD_CELL_PIN}] \
    [all_outputs]

# ----------------------------------------------------------------------
# 5. Input delays -- IMEM/DMEM read-data + reset
#    (all non-clock inputs; single-cycle/no-wait-state memory model)
# ----------------------------------------------------------------------
set_input_delay $INPUT_DELAY -clock $CLK_NAME \
    [get_ports rst_ni]

set_input_delay $INPUT_DELAY -clock $CLK_NAME \
    [get_ports {imem_rdata_i[*]}]

set_input_delay $INPUT_DELAY -clock $CLK_NAME \
    [get_ports {dmem_rdata_i[*]}]

# ----------------------------------------------------------------------
# 6. Output delays -- IMEM/DMEM address/data/control
# ----------------------------------------------------------------------
set_output_delay $OUTPUT_DELAY -clock $CLK_NAME \
    [get_ports {imem_addr_o[*]}]

set_output_delay $OUTPUT_DELAY -clock $CLK_NAME \
    [get_ports {dmem_addr_o[*]}]

set_output_delay $OUTPUT_DELAY -clock $CLK_NAME \
    [get_ports {dmem_wdata_o[*]}]

set_output_delay $OUTPUT_DELAY -clock $CLK_NAME \
    [get_ports {dmem_be_o[*]}]

set_output_delay $OUTPUT_DELAY -clock $CLK_NAME \
    [get_ports dmem_we_o]

# ----------------------------------------------------------------------
# 7. Design rule / physical-realism constraints
# ----------------------------------------------------------------------
set_max_transition 0.80 [current_design]
set_max_fanout      16   [current_design]

# REMOVED: blanket set_max_capacitance [load_of ...] on current_design
# This lets the synthesis engine safely default to the characterized 
# max_capacitance bounds defined inside the saed32rvt_ss0p7vn40c.db PDK.

# Optional: Apply max capacitance ONLY to external output ports 
# to limit pad boundary load driving
set_max_capacitance 50.0 [all_outputs]

# ----------------------------------------------------------------------
# 7a. Compile Core
# ----------------------------------------------------------------------
compile_ultra -no_autoungroup

# ADD THIS LINE RIGHT HERE:
# Forces the compiler to run a dedicated pass to fix transition/capacitance 
# violations without messing with your closed setup timing.
compile_ultra -incremental -only_design_rules

# FOUNDRY DELTA
# A real commercial 32nm (or smaller) foundry PDK would typically require
# multiple standard-cell track heights / drive-strength ladders per cell,
# separate max_transition/max_capacitance rules per voltage area, and
# multi-corner multi-mode (MCMM) scenario setup (at minimum: func/ss/cold,
# func/ff/hot, and often cworst/rcworst RC corners) applied consistently
# across DC, ICC2, and PrimeTime signoff. This educational flow uses a
# single func::nom scenario at one library corner
# (saed32rvt_ss0p7vn40c.db) throughout, per the class environment spec in
# Section 4.

# ----------------------------------------------------------------------
# 8. Case analysis / unused constraints
#    (none required -- no test/scan/mode-select pins exist on core.sv at
#    the RTL stage; DFT-related case_analysis will be added to the scan-
#    inserted netlist's constraints in Deliverable 6, not here.)
# ----------------------------------------------------------------------
