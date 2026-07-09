// ============================================================================
// id_ex_reg.sv
// Pipeline register between ID and EX.
// flush_i is driven (in core.sv) by: branch_taken_i (EX resolves taken) OR
// hazard_bubble (load-use stall). Either condition zeroes ctrl_o, making
// the instruction occupying EX next cycle fully inert (no reg/mem writes,
// no branch/jump effect) regardless of data-field contents.
// ============================================================================

module id_ex_reg
  import rv32i_pkg::*;
(
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    flush_i,

  input  logic [XLEN-1:0]         pc_i,
  input  logic [XLEN-1:0]         pc_plus4_i,
  input  logic [XLEN-1:0]         rs1_data_i,
  input  logic [XLEN-1:0]         rs2_data_i,
  input  logic [REG_ADDR_W-1:0]   rs1_addr_i,
  input  logic [REG_ADDR_W-1:0]   rs2_addr_i,
  input  logic [REG_ADDR_W-1:0]   rd_addr_i,
  input  logic [XLEN-1:0]         imm_ext_i,
  input  ctrl_t                   ctrl_i,

  output logic [XLEN-1:0]         pc_o,
  output logic [XLEN-1:0]         pc_plus4_o,
  output logic [XLEN-1:0]         rs1_data_o,
  output logic [XLEN-1:0]         rs2_data_o,
  output logic [REG_ADDR_W-1:0]   rs1_addr_o,
  output logic [REG_ADDR_W-1:0]   rs2_addr_o,
  output logic [REG_ADDR_W-1:0]   rd_addr_o,
  output logic [XLEN-1:0]         imm_ext_o,
  output ctrl_t                   ctrl_o
);

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      pc_o       <= '0; pc_plus4_o <= '0;
      rs1_data_o <= '0; rs2_data_o <= '0;
      rs1_addr_o <= '0; rs2_addr_o <= '0; rd_addr_o <= '0;
      imm_ext_o  <= '0;
      ctrl_o     <= '0;
    end else if (flush_i) begin
      pc_o       <= '0; pc_plus4_o <= '0;
      rs1_data_o <= '0; rs2_data_o <= '0;
      rs1_addr_o <= '0; rs2_addr_o <= '0; rd_addr_o <= '0;
      imm_ext_o  <= '0;
      ctrl_o     <= '0;
    end else begin
      pc_o       <= pc_i;       pc_plus4_o <= pc_plus4_i;
      rs1_data_o <= rs1_data_i; rs2_data_o <= rs2_data_i;
      rs1_addr_o <= rs1_addr_i; rs2_addr_o <= rs2_addr_i; rd_addr_o <= rd_addr_i;
      imm_ext_o  <= imm_ext_i;
      ctrl_o     <= ctrl_i;
    end
  end

endmodule : id_ex_reg
