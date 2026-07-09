// ============================================================================
// core.sv
// Top-level RV32I 5-stage pipelined core.
// IMEM interface intended for West-side floorplan placement, DMEM interface
// for East-side placement (see 03_floorplan.tcl).
// ============================================================================

module core
  import rv32i_pkg::*;
(
  input  logic             clk_i,
  input  logic             rst_ni,

  // Instruction memory interface (single-cycle, no wait states)
  output logic [XLEN-1:0]  imem_addr_o,
  input  logic [XLEN-1:0]  imem_rdata_i,

  // Data memory interface (single-cycle, no wait states)
  output logic [XLEN-1:0]  dmem_addr_o,
  output logic [XLEN-1:0]  dmem_wdata_o,
  input  logic [XLEN-1:0]  dmem_rdata_i,
  output logic [3:0]       dmem_be_o,
  output logic             dmem_we_o
);

  // IF stage
  logic [XLEN-1:0] if_pc, if_pc_plus4, if_instr;

  // IF/ID register
  logic [XLEN-1:0] ifid_pc, ifid_pc_plus4, ifid_instr;

  // Hazard / flush control
  logic            hazard_stall, hazard_bubble;
  logic            branch_taken;
  logic [XLEN-1:0] branch_target;

  // ID stage
  logic [REG_ADDR_W-1:0] id_rs1_addr, id_rs2_addr, id_rd_addr;
  logic [XLEN-1:0]       id_rs1_data, id_rs2_data, id_imm_ext;
  ctrl_t                 id_ctrl;

  // ID/EX register
  logic [XLEN-1:0]       idex_pc, idex_pc_plus4, idex_rs1_data, idex_rs2_data, idex_imm_ext;
  logic [REG_ADDR_W-1:0] idex_rs1_addr, idex_rs2_addr, idex_rd_addr;
  ctrl_t                 idex_ctrl;

  // Forwarding unit
  fwd_sel_e fwd_a_sel, fwd_b_sel;

  // EX stage
  logic [XLEN-1:0]       ex_alu_result, ex_store_data, ex_pc_plus4;
  logic [REG_ADDR_W-1:0] ex_rd_addr;
  ctrl_t                 ex_ctrl;

  // EX/MEM register
  logic [XLEN-1:0]       exmem_alu_result, exmem_store_data, exmem_pc_plus4;
  logic [REG_ADDR_W-1:0] exmem_rd_addr;
  ctrl_t                 exmem_ctrl;

  // MEM stage
  logic [XLEN-1:0] mem_rdata_ext;

  // MEM/WB register
  logic [XLEN-1:0]       memwb_alu_result, memwb_mem_rdata, memwb_pc_plus4;
  logic [REG_ADDR_W-1:0] memwb_rd_addr;
  ctrl_t                 memwb_ctrl;

  // Writeback + forwarding data buses
  logic [XLEN-1:0] wb_data;
  logic [XLEN-1:0] ex_mem_fwd_data;

  // ------------------------------------------------------------------
  // IF
  // ------------------------------------------------------------------
  if_stage u_if_stage (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .stall_if_i       (hazard_stall),
    .branch_taken_i   (branch_taken),
    .branch_target_i  (branch_target),
    .imem_addr_o      (imem_addr_o),
    .imem_rdata_i     (imem_rdata_i),
    .pc_o             (if_pc),
    .pc_plus4_o       (if_pc_plus4),
    .instr_o          (if_instr)
  );

  if_id_reg u_if_id_reg (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .stall_i     (hazard_stall),
    .flush_i     (branch_taken),
    .pc_i        (if_pc),
    .pc_plus4_i  (if_pc_plus4),
    .instr_i     (if_instr),
    .pc_o        (ifid_pc),
    .pc_plus4_o  (ifid_pc_plus4),
    .instr_o     (ifid_instr)
  );

  // ------------------------------------------------------------------
  // ID
  // ------------------------------------------------------------------
  decode_stage u_decode_stage (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .instr_i         (ifid_instr),
    .reg_write_wb_i  (memwb_ctrl.reg_write),
    .rd_addr_wb_i    (memwb_rd_addr),
    .rd_data_wb_i    (wb_data),
    .rs1_addr_o      (id_rs1_addr),
    .rs2_addr_o      (id_rs2_addr),
    .rd_addr_o       (id_rd_addr),
    .rs1_data_o      (id_rs1_data),
    .rs2_data_o      (id_rs2_data),
    .imm_ext_o       (id_imm_ext),
    .ctrl_o          (id_ctrl)
  );

  hazard_unit u_hazard_unit (
    .id_rs1_addr_i (id_rs1_addr),
    .id_rs2_addr_i (id_rs2_addr),
    .ex_mem_read_i (idex_ctrl.mem_read),
    .ex_rd_addr_i  (idex_rd_addr),
    .stall_o       (hazard_stall),
    .bubble_o      (hazard_bubble)
  );

  id_ex_reg u_id_ex_reg (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .flush_i      (branch_taken | hazard_bubble),
    .pc_i         (ifid_pc),
    .pc_plus4_i   (ifid_pc_plus4),
    .rs1_data_i   (id_rs1_data),
    .rs2_data_i   (id_rs2_data),
    .rs1_addr_i   (id_rs1_addr),
    .rs2_addr_i   (id_rs2_addr),
    .rd_addr_i    (id_rd_addr),
    .imm_ext_i    (id_imm_ext),
    .ctrl_i       (id_ctrl),
    .pc_o         (idex_pc),
    .pc_plus4_o   (idex_pc_plus4),
    .rs1_data_o   (idex_rs1_data),
    .rs2_data_o   (idex_rs2_data),
    .rs1_addr_o   (idex_rs1_addr),
    .rs2_addr_o   (idex_rs2_addr),
    .rd_addr_o    (idex_rd_addr),
    .imm_ext_o    (idex_imm_ext),
    .ctrl_o       (idex_ctrl)
  );

  // ------------------------------------------------------------------
  // EX
  // ------------------------------------------------------------------
  forwarding_unit u_forwarding_unit (
    .ex_rs1_addr_i       (idex_rs1_addr),
    .ex_rs2_addr_i       (idex_rs2_addr),
    .ex_mem_reg_write_i  (exmem_ctrl.reg_write),
    .ex_mem_rd_addr_i    (exmem_rd_addr),
    .mem_wb_reg_write_i  (memwb_ctrl.reg_write),
    .mem_wb_rd_addr_i    (memwb_rd_addr),
    .fwd_a_sel_o         (fwd_a_sel),
    .fwd_b_sel_o         (fwd_b_sel)
  );

  assign ex_mem_fwd_data = (exmem_ctrl.wb_sel == WB_SEL_PC4) ? exmem_pc_plus4 : exmem_alu_result;

  ex_stage u_ex_stage (
    .pc_i               (idex_pc),
    .pc_plus4_i         (idex_pc_plus4),
    .rs1_data_i         (idex_rs1_data),
    .rs2_data_i         (idex_rs2_data),
    .rd_addr_i          (idex_rd_addr),
    .imm_ext_i          (idex_imm_ext),
    .ctrl_i             (idex_ctrl),
    .fwd_a_sel_i        (fwd_a_sel),
    .fwd_b_sel_i        (fwd_b_sel),
    .ex_mem_fwd_data_i  (ex_mem_fwd_data),
    .wb_fwd_data_i      (wb_data),
    .alu_result_o       (ex_alu_result),
    .store_data_o       (ex_store_data),
    .rd_addr_o          (ex_rd_addr),
    .pc_plus4_o         (ex_pc_plus4),
    .ctrl_o             (ex_ctrl),
    .branch_taken_o     (branch_taken),
    .branch_target_o    (branch_target)
  );

  ex_mem_reg u_ex_mem_reg (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .alu_result_i  (ex_alu_result),
    .store_data_i  (ex_store_data),
    .rd_addr_i     (ex_rd_addr),
    .pc_plus4_i    (ex_pc_plus4),
    .ctrl_i        (ex_ctrl),
    .alu_result_o  (exmem_alu_result),
    .store_data_o  (exmem_store_data),
    .rd_addr_o     (exmem_rd_addr),
    .pc_plus4_o    (exmem_pc_plus4),
    .ctrl_o        (exmem_ctrl)
  );

  // ------------------------------------------------------------------
  // MEM
  // ------------------------------------------------------------------
  mem_stage u_mem_stage (
    .alu_result_i  (exmem_alu_result),
    .store_data_i  (exmem_store_data),
    .ctrl_i        (exmem_ctrl),
    .dmem_addr_o   (dmem_addr_o),
    .dmem_wdata_o  (dmem_wdata_o),
    .dmem_be_o     (dmem_be_o),
    .dmem_we_o     (dmem_we_o),
    .dmem_rdata_i  (dmem_rdata_i),
    .mem_rdata_o   (mem_rdata_ext)
  );

  mem_wb_reg u_mem_wb_reg (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .alu_result_i  (exmem_alu_result),
    .mem_rdata_i   (mem_rdata_ext),
    .pc_plus4_i    (exmem_pc_plus4),
    .rd_addr_i     (exmem_rd_addr),
    .ctrl_i        (exmem_ctrl),
    .alu_result_o  (memwb_alu_result),
    .mem_rdata_o   (memwb_mem_rdata),
    .pc_plus4_o    (memwb_pc_plus4),
    .rd_addr_o     (memwb_rd_addr),
    .ctrl_o        (memwb_ctrl)
  );

  // ------------------------------------------------------------------
  // WB (mux only — reused for reg-file write data and MEM/WB->EX forward)
  // ------------------------------------------------------------------
  always_comb begin
    unique case (memwb_ctrl.wb_sel)
      WB_SEL_ALU: wb_data = memwb_alu_result;
      WB_SEL_MEM: wb_data = memwb_mem_rdata;
      WB_SEL_PC4: wb_data = memwb_pc_plus4;
      default:    wb_data = memwb_alu_result;
    endcase
  end

endmodule : core
