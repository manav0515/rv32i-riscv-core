// ============================================================================
// forwarding_unit.sv
// Determines EX-stage operand forwarding sources.
// Priority: EX/MEM (more recent) over MEM/WB.
// ============================================================================

module forwarding_unit
  import rv32i_pkg::*;
(
  input  logic [REG_ADDR_W-1:0] ex_rs1_addr_i,
  input  logic [REG_ADDR_W-1:0] ex_rs2_addr_i,

  input  logic                  ex_mem_reg_write_i,
  input  logic [REG_ADDR_W-1:0] ex_mem_rd_addr_i,

  input  logic                  mem_wb_reg_write_i,
  input  logic [REG_ADDR_W-1:0] mem_wb_rd_addr_i,

  output fwd_sel_e fwd_a_sel_o,
  output fwd_sel_e fwd_b_sel_o
);

  always_comb begin
    if (ex_mem_reg_write_i && (ex_mem_rd_addr_i != '0) &&
        (ex_mem_rd_addr_i == ex_rs1_addr_i)) begin
      fwd_a_sel_o = FWD_EX_MEM;
    end else if (mem_wb_reg_write_i && (mem_wb_rd_addr_i != '0) &&
                 (mem_wb_rd_addr_i == ex_rs1_addr_i)) begin
      fwd_a_sel_o = FWD_MEM_WB;
    end else begin
      fwd_a_sel_o = FWD_NONE;
    end

    if (ex_mem_reg_write_i && (ex_mem_rd_addr_i != '0) &&
        (ex_mem_rd_addr_i == ex_rs2_addr_i)) begin
      fwd_b_sel_o = FWD_EX_MEM;
    end else if (mem_wb_reg_write_i && (mem_wb_rd_addr_i != '0) &&
                 (mem_wb_rd_addr_i == ex_rs2_addr_i)) begin
      fwd_b_sel_o = FWD_MEM_WB;
    end else begin
      fwd_b_sel_o = FWD_NONE;
    end
  end

endmodule : forwarding_unit
