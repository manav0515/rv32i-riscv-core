// ============================================================================
// if_id_reg.sv
// Pipeline register between IF and ID.
// - stall_i:  hold current contents (load-use hazard freeze)
// - flush_i:  squash — load architectural NOP (taken branch/jump)
// Priority: flush > stall > normal capture. Active-low SYNCHRONOUS reset.
// ============================================================================

module if_id_reg
  import rv32i_pkg::*;
(
  input  logic             clk_i,
  input  logic             rst_ni,

  input  logic             stall_i,
  input  logic             flush_i,

  input  logic [XLEN-1:0]  pc_i,
  input  logic [XLEN-1:0]  pc_plus4_i,
  input  logic [XLEN-1:0]  instr_i,

  output logic [XLEN-1:0]  pc_o,
  output logic [XLEN-1:0]  pc_plus4_o,
  output logic [XLEN-1:0]  instr_o
);

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      pc_o       <= '0;
      pc_plus4_o <= '0;
      instr_o    <= NOP_INSTR;
    end else if (flush_i) begin
      pc_o       <= '0;
      pc_plus4_o <= '0;
      instr_o    <= NOP_INSTR;
    end else if (stall_i) begin
      // hold: intentionally no assignment, retains previous values
    end else begin
      pc_o       <= pc_i;
      pc_plus4_o <= pc_plus4_i;
      instr_o    <= instr_i;
    end
  end

endmodule : if_id_reg
