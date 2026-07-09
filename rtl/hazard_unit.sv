// ============================================================================
// hazard_unit.sv
// Load-use hazard detection. Compares the load currently in EX (id_ex_reg
// contents) against the source registers of the instruction currently
// decoding in ID (extracted straight from if_id_reg's instruction).
// One-cycle stall + bubble is sufficient given MEM/WB->EX forwarding.
// ============================================================================

module hazard_unit
  import rv32i_pkg::*;
(
  input  logic [REG_ADDR_W-1:0] id_rs1_addr_i,
  input  logic [REG_ADDR_W-1:0] id_rs2_addr_i,
  input  logic                  ex_mem_read_i,
  input  logic [REG_ADDR_W-1:0] ex_rd_addr_i,

  output logic stall_o,   // freeze PC + IF/ID
  output logic bubble_o   // insert bubble into ID/EX
);

  logic load_use_hazard;

  always_comb begin
    load_use_hazard = ex_mem_read_i &&
                       (ex_rd_addr_i != '0) &&
                       ((ex_rd_addr_i == id_rs1_addr_i) ||
                        (ex_rd_addr_i == id_rs2_addr_i));
    stall_o  = load_use_hazard;
    bubble_o = load_use_hazard;
  end

endmodule : hazard_unit
