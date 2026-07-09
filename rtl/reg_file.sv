// ============================================================================
// reg_file.sv
// 32 x 32-bit architectural register file.
// - Two asynchronous (combinational) read ports.
// - One synchronous write port, active-low SYNCHRONOUS reset.
// - x0 hardwired to zero on read; writes to x0 are ignored.
// - Same-cycle write-through bypass: if a read address matches the write
//   address in the same cycle, the read returns the NEW write data rather
//   than stale array contents. This is required for correctness on RAW
//   hazards exactly 3 instructions apart (producer in WB while consumer
//   reads in ID), which occur before EX-stage forwarding would ever see
//   them (the producer has already retired by the time the consumer
//   reaches EX).
// ============================================================================

module reg_file
  import rv32i_pkg::*;
(
  input  logic                     clk_i,
  input  logic                     rst_ni,

  input  logic                     we_i,
  input  logic [REG_ADDR_W-1:0]    waddr_i,
  input  logic [XLEN-1:0]          wdata_i,

  input  logic [REG_ADDR_W-1:0]    raddr1_i,
  input  logic [REG_ADDR_W-1:0]    raddr2_i,
  output logic [XLEN-1:0]          rdata1_o,
  output logic [XLEN-1:0]          rdata2_o
);

  logic [XLEN-1:0] regs_q [0:31];

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      for (int i = 0; i < 32; i++) begin
        regs_q[i] <= '0;
      end
    end else if (we_i && (waddr_i != '0)) begin
      regs_q[waddr_i] <= wdata_i;
    end
  end

  // Asynchronous reads with x0 hardwire and same-cycle write-through bypass
  assign rdata1_o = (raddr1_i == '0) ? '0 :
                     (we_i && (waddr_i == raddr1_i)) ? wdata_i : regs_q[raddr1_i];

  assign rdata2_o = (raddr2_i == '0) ? '0 :
                     (we_i && (waddr_i == raddr2_i)) ? wdata_i : regs_q[raddr2_i];

endmodule : reg_file
