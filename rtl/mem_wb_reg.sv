// ============================================================================
// mem_wb_reg.sv
// Pipeline register between MEM and WB.
// ============================================================================

module mem_wb_reg
  import rv32i_pkg::*;
(
  input  logic                   clk_i,
  input  logic                   rst_ni,

  input  logic [XLEN-1:0]        alu_result_i,
  input  logic [XLEN-1:0]        mem_rdata_i,
  input  logic [XLEN-1:0]        pc_plus4_i,
  input  logic [REG_ADDR_W-1:0]  rd_addr_i,
  input  ctrl_t                  ctrl_i,

  output logic [XLEN-1:0]        alu_result_o,
  output logic [XLEN-1:0]        mem_rdata_o,
  output logic [XLEN-1:0]        pc_plus4_o,
  output logic [REG_ADDR_W-1:0]  rd_addr_o,
  output ctrl_t                  ctrl_o
);

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      alu_result_o <= '0;
      mem_rdata_o  <= '0;
      pc_plus4_o   <= '0;
      rd_addr_o    <= '0;
      ctrl_o       <= '0;
    end else begin
      alu_result_o <= alu_result_i;
      mem_rdata_o  <= mem_rdata_i;
      pc_plus4_o   <= pc_plus4_i;
      rd_addr_o    <= rd_addr_i;
      ctrl_o       <= ctrl_i;
    end
  end

endmodule : mem_wb_reg
