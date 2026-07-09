// ============================================================================
// if_stage.sv
//
// IF (Instruction Fetch) stage of the 5-stage RV32I pipeline.
//
// Responsibilities:
//   - Maintain the architectural program counter (PC).
//   - Select next PC: EX-stage branch/jump redirect > hazard-unit stall
//     (hold) > sequential PC+4.
//   - Drive the single-cycle, zero-wait-state instruction memory interface
//     and present the fetched instruction plus PC/PC+4 to the if_id_reg
//     pipeline register.
//
// Notes:
//   - Instruction memory is modeled as a combinational-read, single-cycle
//     interface per the project's memory-interface assumption: the address
//     driven this cycle returns valid data within the same cycle
//     (no wait states, no explicit request/ack handshake).
//   - Reset is active-low and SYNCHRONOUS (sampled only on the clock edge),
//     per project convention.
// ============================================================================

module if_stage
  import rv32i_pkg::*;
(
  input  logic             clk_i,
  input  logic             rst_ni,

  // --- Pipeline control (from Hazard Detection Unit / EX stage) ---------
  input  logic             stall_if_i,      // hold PC (e.g. load-use hazard)
  input  logic             branch_taken_i,  // redirect from EX stage (branch/jump resolved taken)
  input  logic [XLEN-1:0]  branch_target_i, // redirect target address from EX stage

  // --- Instruction memory interface (single-cycle, no wait states) ------
  output logic [XLEN-1:0]  imem_addr_o,
  input  logic [XLEN-1:0]  imem_rdata_i,

  // --- Outputs to if_id_reg -----------------------------------------------
  output logic [XLEN-1:0]  pc_o,
  output logic [XLEN-1:0]  pc_plus4_o,
  output logic [XLEN-1:0]  instr_o
);

  logic [XLEN-1:0] pc_q, pc_d;

  // ------------------------------------------------------------------
  // Next-PC select mux
  // Priority: branch/jump redirect > stall (hold) > sequential PC+4
  // ------------------------------------------------------------------
  always_comb begin : next_pc_mux
    if (branch_taken_i) begin
      pc_d = branch_target_i;
    end else if (stall_if_i) begin
      pc_d = pc_q;
    end else begin
      pc_d = pc_q + 32'd4;
    end
  end

  // ------------------------------------------------------------------
  // Program counter register (active-low SYNCHRONOUS reset)
  // ------------------------------------------------------------------
  always_ff @(posedge clk_i) begin : pc_reg
    if (!rst_ni) begin
      pc_q <= RESET_VECTOR;
    end else begin
      pc_q <= pc_d;
    end
  end

  // ------------------------------------------------------------------
  // Instruction memory drive + stage outputs
  // ------------------------------------------------------------------
  assign imem_addr_o = pc_q;
  assign pc_o         = pc_q;
  assign pc_plus4_o   = pc_q + 32'd4;
  assign instr_o      = imem_rdata_i;

endmodule : if_stage
