// ============================================================================
// rv32i_pkg.sv
//
// Global package for the 5-stage pipelined RV32I core.
// Contains shared parameters, opcode encodings, and control-signal typedefs
// used across all pipeline stages and pipeline register modules.
//
// This package MUST be imported by every RTL module in the design
// (`import rv32i_pkg::*;`) to guarantee a single, consistent source of
// truth for encodings and bus widths across the hierarchy.
// ============================================================================

package rv32i_pkg;

  // --------------------------------------------------------------------
  // Global datapath parameters
  // --------------------------------------------------------------------
  parameter int XLEN = 32;                              // architectural register/data width
  parameter int REG_ADDR_W = 5;                          // 32 architectural registers (x0-x31)
  parameter logic [XLEN-1:0] RESET_VECTOR = 32'h0000_0000; // PC value on reset
  parameter logic [XLEN-1:0] NOP_INSTR = 32'h0000_0013;    // ADDI x0, x0, 0 (architectural NOP)

  // --------------------------------------------------------------------
  // Opcodes (instruction bits [6:0])
  // --------------------------------------------------------------------
  parameter logic [6:0] OPCODE_R_TYPE = 7'b0110011; // ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND
  parameter logic [6:0] OPCODE_I_ALU  = 7'b0010011; // ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI
  parameter logic [6:0] OPCODE_LOAD   = 7'b0000011; // LB/LH/LW/LBU/LHU
  parameter logic [6:0] OPCODE_STORE  = 7'b0100011; // SB/SH/SW
  parameter logic [6:0] OPCODE_BRANCH = 7'b1100011; // BEQ/BNE/BLT/BGE/BLTU/BGEU
  parameter logic [6:0] OPCODE_JAL    = 7'b1101111;
  parameter logic [6:0] OPCODE_JALR   = 7'b1100111;
  parameter logic [6:0] OPCODE_LUI    = 7'b0110111;
  parameter logic [6:0] OPCODE_AUIPC  = 7'b0010111;

  // --------------------------------------------------------------------
  // ALU operation select (produced by decode, consumed by EX)
  // --------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD    = 4'b0000,
    ALU_SUB    = 4'b0001,
    ALU_SLL    = 4'b0010,
    ALU_SLT    = 4'b0011,
    ALU_SLTU   = 4'b0100,
    ALU_XOR    = 4'b0101,
    ALU_SRL    = 4'b0110,
    ALU_SRA    = 4'b0111,
    ALU_OR     = 4'b1000,
    ALU_AND    = 4'b1001,
    ALU_PASS_B = 4'b1010  // pass operand B through unmodified (used by LUI)
  } alu_op_e;

  // --------------------------------------------------------------------
  // Branch condition select (branch resolved combinationally in EX)
  // --------------------------------------------------------------------
  typedef enum logic [2:0] {
    BR_NONE = 3'b000,
    BR_EQ   = 3'b001,  // BEQ
    BR_NE   = 3'b010,  // BNE
    BR_LT   = 3'b011,  // BLT  (signed)
    BR_GE   = 3'b100,  // BGE  (signed)
    BR_LTU  = 3'b101,  // BLTU (unsigned)
    BR_GEU  = 3'b110   // BGEU (unsigned)
  } branch_type_e;

  // --------------------------------------------------------------------
  // ALU operand source selects
  // --------------------------------------------------------------------
  typedef enum logic [1:0] {
    OP_A_RS1  = 2'b00,
    OP_A_PC   = 2'b01,  // AUIPC / JAL / JALR / branch target adder
    OP_A_ZERO = 2'b10   // LUI (0 + imm)
  } alu_op_a_sel_e;

  typedef enum logic [1:0] {
    OP_B_RS2  = 2'b00,
    OP_B_IMM  = 2'b01,
    OP_B_FOUR = 2'b10   // reserved (link address alt. path, unused currently)
  } alu_op_b_sel_e;

  // --------------------------------------------------------------------
  // Immediate format select (decoded from opcode in ID stage)
  // --------------------------------------------------------------------
  typedef enum logic [2:0] {
    IMM_I = 3'b000,
    IMM_S = 3'b001,
    IMM_B = 3'b010,
    IMM_U = 3'b011,
    IMM_J = 3'b100
  } imm_sel_e;

  // --------------------------------------------------------------------
  // Writeback source select
  // --------------------------------------------------------------------
  typedef enum logic [1:0] {
    WB_SEL_ALU = 2'b00,
    WB_SEL_MEM = 2'b01,
    WB_SEL_PC4 = 2'b10   // JAL / JALR link value
  } wb_sel_e;

  // --------------------------------------------------------------------
  // Load/store size + sign encoding (mirrors funct3 field directly)
  // --------------------------------------------------------------------
  typedef enum logic [2:0] {
    MEM_SIZE_BYTE   = 3'b000, // LB/SB
    MEM_SIZE_HALF   = 3'b001, // LH/SH
    MEM_SIZE_WORD   = 3'b010, // LW/SW
    MEM_SIZE_BYTE_U = 3'b100, // LBU
    MEM_SIZE_HALF_U = 3'b101  // LHU
  } mem_size_e;

  // --------------------------------------------------------------------
  // Forwarding source select (produced by forwarding_unit, consumed by EX)
  // --------------------------------------------------------------------
  typedef enum logic [1:0] {
    FWD_NONE   = 2'b00, // use value already latched in id_ex_reg
    FWD_EX_MEM = 2'b01, // forward from EX/MEM pipeline register
    FWD_MEM_WB = 2'b10  // forward from MEM/WB pipeline register
  } fwd_sel_e;

  // --------------------------------------------------------------------
  // Bundled control-signal struct.
  //
  // Rationale: packing all decode-generated control signals into a single
  // packed struct lets each pipeline register (id_ex_reg, ex_mem_reg,
  // mem_wb_reg) carry them as one field instead of dozens of individual
  // single-bit flops. This keeps pipeline register modules compact and
  // avoids an unstructured "sea of flops" during synthesis/placement.
  // --------------------------------------------------------------------
  typedef struct packed {
    logic          reg_write;   // architectural register file write enable
    wb_sel_e       wb_sel;      // writeback mux select
    logic          mem_read;    // data memory read enable
    logic          mem_write;   // data memory write enable
    mem_size_e     mem_size;    // load/store width + sign
    alu_op_a_sel_e op_a_sel;    // ALU operand A mux select
    alu_op_b_sel_e op_b_sel;    // ALU operand B mux select
    alu_op_e       alu_op;      // ALU operation
    logic          branch;      // instruction is a conditional branch
    logic          jump;        // instruction is JAL or JALR (unconditional)
    branch_type_e  branch_type; // branch condition code
    imm_sel_e      imm_sel;     // immediate format select
  } ctrl_t;

endpackage : rv32i_pkg
