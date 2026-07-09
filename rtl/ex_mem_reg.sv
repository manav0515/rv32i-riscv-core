// ============================================================================
// ex_mem_reg.sv
// Pipeline register between EX and MEM. No stall/flush needed here: once an
// instruction is past EX, branch resolution and hazard squashing have
// already been applied upstream, so this stage always advances.
// ============================================================================

module ex_mem_reg
  import rv32i_pkg::*;
(
  input  logic                   clk_i,
  input  logic                   rst_ni,

  input  logic [XLEN-1:0]        alu_result_i,
  input  logic [XLEN-1:0]        store_data_i,
  input  logic [REG_ADDR_W-1:0]  rd_addr_i,
  input  logic [XLEN-1:0]        pc_plus4_i,
  input  ctrl_t                  ctrl_i,

  output logic [XLEN-1:0]        alu_result_o,
  output logic [XLEN-1:0]        store_data_o,
  output logic [REG_ADDR_W-1:0]  rd_addr_o,
  output logic [XLEN-1:0]        pc_plus4_o,
  output ctrl_t                  ctrl_o
);

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      alu_result_o <= '0;
      store_data_o <= '0;
      rd_addr_o    <= '0;
      pc_plus4_o   <= '0;
      ctrl_o       <= '0;
    end else begin
      alu_result_o <= alu_result_i;
      store_data_o <= store_data_i;
      rd_addr_o    <= rd_addr_i;
      pc_plus4_o   <= pc_plus4_i;
      ctrl_o       <= ctrl_i;
    end
  end

endmodule : ex_mem_reg
