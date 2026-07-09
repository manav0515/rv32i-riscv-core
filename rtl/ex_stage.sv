// ============================================================================
// ex_stage.sv
// EX stage: forwarding muxes (rs1/rs2), ALU operand muxes, ALU instance,
// branch condition evaluation, and branch/jump target calculation.
//
// - Forwarding is applied to the RAW rs1/rs2 values (rs1_fwd/rs2_fwd) before
//   the op_a_sel/op_b_sel muxes select what actually feeds the ALU. This
//   means store data (rs2_fwd) and the branch comparator both see correctly
//   forwarded values independent of how the ALU operands are configured.
// - JALR target has bit 0 cleared per the RISC-V spec; JALR is identified
//   as (ctrl_i.jump && ctrl_i.op_a_sel == OP_A_RS1), since JAL always uses
//   OP_A_PC while JALR always uses OP_A_RS1 in this decode scheme.
// ============================================================================

module ex_stage
  import rv32i_pkg::*;
(
  input  logic [XLEN-1:0]        pc_i,
  input  logic [XLEN-1:0]        pc_plus4_i,
  input  logic [XLEN-1:0]        rs1_data_i,
  input  logic [XLEN-1:0]        rs2_data_i,
  input  logic [REG_ADDR_W-1:0]  rd_addr_i,
  input  logic [XLEN-1:0]        imm_ext_i,
  input  ctrl_t                  ctrl_i,

  input  fwd_sel_e               fwd_a_sel_i,
  input  fwd_sel_e               fwd_b_sel_i,
  input  logic [XLEN-1:0]        ex_mem_fwd_data_i, // EX/MEM -> EX forward value
  input  logic [XLEN-1:0]        wb_fwd_data_i,      // MEM/WB -> EX forward value

  output logic [XLEN-1:0]        alu_result_o,
  output logic [XLEN-1:0]        store_data_o,
  output logic [REG_ADDR_W-1:0]  rd_addr_o,
  output logic [XLEN-1:0]        pc_plus4_o,
  output ctrl_t                  ctrl_o,

  output logic                   branch_taken_o,
  output logic [XLEN-1:0]        branch_target_o
);

  logic [XLEN-1:0] rs1_fwd, rs2_fwd;
  logic [XLEN-1:0] alu_operand_a, alu_operand_b;
  logic [XLEN-1:0] alu_result;
  logic            branch_cond;
  logic            is_jalr;

  // ------------------------------------------------------------------
  // Forwarding muxes
  // ------------------------------------------------------------------
  always_comb begin
    unique case (fwd_a_sel_i)
      FWD_EX_MEM: rs1_fwd = ex_mem_fwd_data_i;
      FWD_MEM_WB: rs1_fwd = wb_fwd_data_i;
      default:    rs1_fwd = rs1_data_i;
    endcase
  end

  always_comb begin
    unique case (fwd_b_sel_i)
      FWD_EX_MEM: rs2_fwd = ex_mem_fwd_data_i;
      FWD_MEM_WB: rs2_fwd = wb_fwd_data_i;
      default:    rs2_fwd = rs2_data_i;
    endcase
  end

  // ------------------------------------------------------------------
  // ALU operand muxes
  // ------------------------------------------------------------------
  always_comb begin
    unique case (ctrl_i.op_a_sel)
      OP_A_RS1:  alu_operand_a = rs1_fwd;
      OP_A_PC:   alu_operand_a = pc_i;
      OP_A_ZERO: alu_operand_a = '0;
      default:   alu_operand_a = rs1_fwd;
    endcase
  end

  always_comb begin
    unique case (ctrl_i.op_b_sel)
      OP_B_RS2:  alu_operand_b = rs2_fwd;
      OP_B_IMM:  alu_operand_b = imm_ext_i;
      OP_B_FOUR: alu_operand_b = 32'd4;
      default:   alu_operand_b = rs2_fwd;
    endcase
  end

  alu u_alu (
    .operand_a_i (alu_operand_a),
    .operand_b_i (alu_operand_b),
    .alu_op_i    (ctrl_i.alu_op),
    .result_o    (alu_result)
  );

  // ------------------------------------------------------------------
  // Branch condition evaluation (independent of ALU operand muxing)
  // ------------------------------------------------------------------
  always_comb begin
    unique case (ctrl_i.branch_type)
      BR_EQ:   branch_cond = (rs1_fwd == rs2_fwd);
      BR_NE:   branch_cond = (rs1_fwd != rs2_fwd);
      BR_LT:   branch_cond = ($signed(rs1_fwd) <  $signed(rs2_fwd));
      BR_GE:   branch_cond = ($signed(rs1_fwd) >= $signed(rs2_fwd));
      BR_LTU:  branch_cond = (rs1_fwd <  rs2_fwd);
      BR_GEU:  branch_cond = (rs1_fwd >= rs2_fwd);
      default: branch_cond = 1'b0;
    endcase
  end

  assign is_jalr         = ctrl_i.jump && (ctrl_i.op_a_sel == OP_A_RS1);
  assign branch_target_o = is_jalr ? {alu_result[31:1], 1'b0} : alu_result;
  assign branch_taken_o  = ctrl_i.jump || (ctrl_i.branch && branch_cond);

  // ------------------------------------------------------------------
  // Stage outputs
  // ------------------------------------------------------------------
  assign alu_result_o = alu_result;
  assign store_data_o  = rs2_fwd;
  assign rd_addr_o     = rd_addr_i;
  assign pc_plus4_o    = pc_plus4_i;
  assign ctrl_o        = ctrl_i;

endmodule : ex_stage
