# ============================================================================
# dc.tcl
#
# Synopsys Design Compiler synthesis script for the RV32I 5-stage pipelined
# core (top module: core).
# ============================================================================

# ----------------------------------------------------------------------
# 1. Environment / Absolute Path Setup
# ----------------------------------------------------------------------
set PDK_LIB_DIR     "/home/student/Documents/Manav/RTL2GDSII/Workshop/ref/lib/stdcell_rvt"
set RTL_DIR         "/home/student/Documents/Manav/Design"
set OUT_DIR         "/home/student/Documents/Manav/rv32i_outputs"
set REPORT_DIR      "/home/student/Documents/Manav/rv32i_reports"
set WORK_DIR        "/home/student/Documents/Manav/rv32i_work"

# Ensure output and report directories exist
file mkdir $OUT_DIR
file mkdir $REPORT_DIR
file mkdir $WORK_DIR

set TARGET_LIB      "saed32rvt_ss0p7vn40c.db"
set TOP_MODULE      "core"

# ----------------------------------------------------------------------
# 2. Library Setup
# ----------------------------------------------------------------------
set search_path [list \
    . \
    $RTL_DIR \
    $PDK_LIB_DIR \
]

set target_library [list $TARGET_LIB]
set link_library    [concat "*" $target_library]

# ----------------------------------------------------------------------
# 3. Global DC Synthesis Settings
# ----------------------------------------------------------------------
set_app_var hdlin_check_no_latch true
set_app_var compile_ultra_ungroup_dw false
set_app_var alib_library_analysis_path "${WORK_DIR}/alib"

# ----------------------------------------------------------------------
# 4. Read + Analyze RTL (Strict Build Order)
# ----------------------------------------------------------------------
define_design_lib WORK -path $WORK_DIR

analyze -format sverilog -library WORK [list \
    ${RTL_DIR}/rv32i_pkg.sv    \
    ${RTL_DIR}/if_stage.sv     \
    ${RTL_DIR}/if_id_reg.sv    \
    ${RTL_DIR}/reg_file.sv     \
    ${RTL_DIR}/decode_stage.sv \
    ${RTL_DIR}/id_ex_reg.sv    \
    ${RTL_DIR}/alu.sv          \
    ${RTL_DIR}/ex_stage.sv     \
    ${RTL_DIR}/ex_mem_reg.sv   \
    ${RTL_DIR}/mem_stage.sv    \
    ${RTL_DIR}/mem_wb_reg.sv   \
    ${RTL_DIR}/hazard_unit.sv  \
    ${RTL_DIR}/forwarding_unit.sv \
    ${RTL_DIR}/core.sv         \
]

# ----------------------------------------------------------------------
# 5. Elaborate Top-Level Design (Fixed Architecture Error)
# ----------------------------------------------------------------------
elaborate $TOP_MODULE -library WORK

current_design $TOP_MODULE
link

uniquify

# ----------------------------------------------------------------------
# 6. Apply Constraints
# ----------------------------------------------------------------------
source -echo -verbose "${RTL_DIR}/core.sdc"

check_design > ${REPORT_DIR}/${TOP_MODULE}_check_design_pre_compile.rpt

# ----------------------------------------------------------------------
# 7. Compile
# ----------------------------------------------------------------------
set_fix_multiple_port_nets -all -buffer_constants
compile_ultra -no_autoungroup

# ----------------------------------------------------------------------
# 8. Post-Compile Checks and Reporting
# ----------------------------------------------------------------------
check_design > ${REPORT_DIR}/${TOP_MODULE}_check_design_post_compile.rpt

report_area -hierarchy > ${REPORT_DIR}/${TOP_MODULE}_area.rpt
report_power -hierarchy > ${REPORT_DIR}/${TOP_MODULE}_power.rpt
report_timing -delay_type max -max_paths 10 > ${REPORT_DIR}/${TOP_MODULE}_timing_max.rpt
report_timing -delay_type min -max_paths 10 > ${REPORT_DIR}/${TOP_MODULE}_timing_min.rpt
report_qor > ${REPORT_DIR}/${TOP_MODULE}_qor.rpt
report_constraint -all_violators -verbose > ${REPORT_DIR}/${TOP_MODULE}_constraints.rpt

# ----------------------------------------------------------------------
# 9. Write Mapped Outputs
# ----------------------------------------------------------------------
change_names -rules verilog -hierarchy
write_file -format verilog -hierarchy -output ${OUT_DIR}/${TOP_MODULE}_syn.v
write_sdc ${OUT_DIR}/${TOP_MODULE}_syn.sdc
write -format ddc -hierarchy -output ${OUT_DIR}/${TOP_MODULE}_syn.ddc

report_design > ${REPORT_DIR}/${TOP_MODULE}_design_summary.rpt
#quit
