// ============================================================================
// decode_stage.sv
// ID stage: instruction field extraction, main control decode, immediate
// generation, and register file instantiation (register reads happen here).
//
// Note on hazard detection simplification: rs1_addr_o/rs2_addr_o are always
// extracted from the raw instruction fields regardless of whether the
// instruction actually consumes them (e.g. LUI/AUIPC/JAL). The Hazard
// Detection Unit treats these conservatively, which can occasionally cause
// a redundant stall but never an incorrect result. Per the project's stated
// priority (correctness/synthesizability over microarchitectural
// optimization), this simplification is intentional.
// ============================================================================

module decode_stage
  import rv32i_pkg::*;
(
  input  logic                    clk_i,
  input  logic                    rst_ni,

  input  logic [XLEN-1:0]         instr_i,

  // Register file write port (driven from WB stage via core.sv)
  input  logic                    reg_write_wb_i,
  input  logic [REG_ADDR_W-1:0]   rd_addr_wb_i,
  input  logic [XLEN-1:0]         rd_data_wb_i,

  output logic [REG_ADDR_W-1:0]   rs1_addr_o,
  output logic [REG_ADDR_W-1:0]   rs2_addr_o,
  output logic [REG_ADDR_W-1:0]   rd_addr_o,
  output logic [XLEN-1:0]         rs1_data_o,
  output logic [XLEN-1:0]         rs2_data_o,
  output logic [XLEN-1:0]         imm_ext_o,
  output ctrl_t                   ctrl_o
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic       funct7b5;

  assign opcode     = instr_i[6:0];
  assign rd_addr_o  = instr_i[11:7];
  assign funct3     = instr_i[14:12];
  assign rs1_addr_o = instr_i[19:15];
  assign rs2_addr_o = instr_i[24:20];
  assign funct7b5   = instr_i[30];

  reg_file u_reg_file (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .we_i     (reg_write_wb_i),
    .waddr_i  (rd_addr_wb_i),
    .wdata_i  (rd_data_wb_i),
    .raddr1_i (rs1_addr_o),
    .raddr2_i (rs2_addr_o),
    .rdata1_o (rs1_data_o),
    .rdata2_o (rs2_data_o)
  );

  // ------------------------------------------------------------------
  // ALU op decode.
  // is_reg_reg distinguishes R-type (funct7[5] is a real ADD/SUB select)
  // from I-type ADDI (instr[30] is part of the immediate, NOT a SUB
  // selector). For funct3=101 (shift), instr[30] is a genuine SRLI/SRAI
  // selector for BOTH R-type and I-type per the RISC-V encoding.
  // ------------------------------------------------------------------
  function automatic alu_op_e decode_alu_op(input logic [2:0] f3,
                                             input logic       f7b5,
                                             input logic       is_reg_reg);
    unique case (f3)
      3'b000:  decode_alu_op = (is_reg_reg && f7b5) ? ALU_SUB : ALU_ADD;
      3'b001:  decode_alu_op = ALU_SLL;
      3'b010:  decode_alu_op = ALU_SLT;
      3'b011:  decode_alu_op = ALU_SLTU;
      3'b100:  decode_alu_op = ALU_XOR;
      3'b101:  decode_alu_op = f7b5 ? ALU_SRA : ALU_SRL;
      3'b110:  decode_alu_op = ALU_OR;
      3'b111:  decode_alu_op = ALU_AND;
      default: decode_alu_op = ALU_ADD;
    endcase
  endfunction

  function automatic branch_type_e decode_branch_type(input logic [2:0] f3);
    unique case (f3)
      3'b000:  decode_branch_type = BR_EQ;
      3'b001:  decode_branch_type = BR_NE;
      3'b100:  decode_branch_type = BR_LT;
      3'b101:  decode_branch_type = BR_GE;
      3'b110:  decode_branch_type = BR_LTU;
      3'b111:  decode_branch_type = BR_GEU;
      default: decode_branch_type = BR_NONE;
    endcase
  endfunction

  function automatic imm_sel_e decode_imm_sel(input logic [6:0] op);
    unique case (op)
      OPCODE_STORE:              decode_imm_sel = IMM_S;
      OPCODE_BRANCH:             decode_imm_sel = IMM_B;
      OPCODE_LUI, OPCODE_AUIPC:  decode_imm_sel = IMM_U;
      OPCODE_JAL:                decode_imm_sel = IMM_J;
      default:                   decode_imm_sel = IMM_I; // I_ALU, LOAD, JALR
    endcase
  endfunction

  // ------------------------------------------------------------------
  // Main control decode
  // ------------------------------------------------------------------
  always_comb begin
    ctrl_o          = '0;
    ctrl_o.alu_op   = ALU_ADD;
    ctrl_o.imm_sel  = decode_imm_sel(opcode);

    unique case (opcode)
      OPCODE_R_TYPE: begin
        ctrl_o.reg_write = 1'b1;
        ctrl_o.wb_sel    = WB_SEL_ALU;
        ctrl_o.op_a_sel  = OP_A_RS1;
        ctrl_o.op_b_sel  = OP_B_RS2;
        ctrl_o.alu_op    = decode_alu_op(funct3, funct7b5, 1'b1);
      end

      OPCODE_I_ALU: begin
        ctrl_o.reg_write = 1'b1;
        ctrl_o.wb_sel    = WB_SEL_ALU;
        ctrl_o.op_a_sel  = OP_A_RS1;
        ctrl_o.op_b_sel  = OP_B_IMM;
        ctrl_o.alu_op    = decode_alu_op(funct3, funct7b5, 1'b0);
      end

      OPCODE_LOAD: begin
        ctrl_o.reg_write = 1'b1;
        ctrl_o.wb_sel    = WB_SEL_MEM;
        ctrl_o.mem_read  = 1'b1;
        ctrl_o.mem_size  = mem_size_e'(funct3);
        ctrl_o.op_a_sel  = OP_A_RS1;
        ctrl_o.op_b_sel  = OP_B_IMM;
        ctrl_o.alu_op    = ALU_ADD;
      end

      OPCODE_STORE: begin
        ctrl_o.mem_write = 1'b1;
        ctrl_o.mem_size  = mem_size_e'(funct3);
        ctrl_o.op_a_sel  = OP_A_RS1;
        ctrl_o.op_b_sel  = OP_B_IMM;
        ctrl_o.alu_op    = ALU_ADD;
      end

      OPCODE_BRANCH: begin
        ctrl_o.branch      = 1'b1;
        ctrl_o.branch_type = decode_branch_type(funct3);
        ctrl_o.op_a_sel    = OP_A_PC;
        ctrl_o.op_b_sel    = OP_B_IMM;
        ctrl_o.alu_op      = ALU_ADD;
      end

      OPCODE_JAL: begin
        // Don't assert reg_write when rd = x0 (e.g. "jal x0,0" halt loop)
        ctrl_o.reg_write = (rd_addr_o != 5'd0);
        ctrl_o.wb_sel    = WB_SEL_PC4;
        ctrl_o.jump      = 1'b1;
        ctrl_o.op_a_sel  = OP_A_PC;
        ctrl_o.op_b_sel  = OP_B_IMM;
        ctrl_o.alu_op    = ALU_ADD;
      end

      OPCODE_JALR: begin
        // Don't assert reg_write when rd = x0
        ctrl_o.reg_write = (rd_addr_o != 5'd0);
        ctrl_o.wb_sel    = WB_SEL_PC4;
        ctrl_o.jump      = 1'b1;
        ctrl_o.op_a_sel  = OP_A_RS1;
        ctrl_o.op_b_sel  = OP_B_IMM;
        ctrl_o.alu_op    = ALU_ADD;
      end

      OPCODE_LUI: begin
        ctrl_o.reg_write = 1'b1;
        ctrl_o.wb_sel    = WB_SEL_ALU;
        ctrl_o.op_a_sel  = OP_A_ZERO;
        ctrl_o.op_b_sel  = OP_B_IMM;
        ctrl_o.alu_op    = ALU_PASS_B;
      end

      OPCODE_AUIPC: begin
        ctrl_o.reg_write = 1'b1;
        ctrl_o.wb_sel    = WB_SEL_ALU;
        ctrl_o.op_a_sel  = OP_A_PC;
        ctrl_o.op_b_sel  = OP_B_IMM;
        ctrl_o.alu_op    = ALU_ADD;
      end

      default: begin
        // Unsupported/illegal opcode -> inert NOP, no architectural side
        // effects. Full illegal-instruction trapping is out of scope
        // (no CSR/exception support per Section 1).
        ctrl_o = '0;
      end
    endcase
  end

  // ------------------------------------------------------------------
  // Immediate generator
  // ------------------------------------------------------------------
  always_comb begin
    unique case (ctrl_o.imm_sel)
      IMM_I:   imm_ext_o = {{20{instr_i[31]}}, instr_i[31:20]};
      IMM_S:   imm_ext_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
      IMM_B:   imm_ext_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                             instr_i[30:25], instr_i[11:8], 1'b0};
      IMM_U:   imm_ext_o = {instr_i[31:12], 12'b0};
      IMM_J:   imm_ext_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                             instr_i[20], instr_i[30:21], 1'b0};
      default: imm_ext_o = {{20{instr_i[31]}}, instr_i[31:20]};
    endcase
  end

endmodule : decode_stage
