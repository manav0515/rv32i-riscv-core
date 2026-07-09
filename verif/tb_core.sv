// ============================================================================
// tb_core.sv
//
// VCS testbench for the RV32I 5-stage pipelined core.
// - Behavioral IMEM/DMEM (single-cycle, zero-wait-state, matching the
//   project's memory-interface assumption).
// - $readmemh-based program loader (test_prog.hex).
// - Directed, hand-assembled program exercising every supported instruction
//   category: ALU R/I-type, shifts, LUI/AUIPC, all load/store widths,
//   taken/not-taken branches, JAL, JALR, a load-use hazard, and back-to-back
//   RAW hazards requiring EX/MEM and MEM/WB forwarding.
// - Dual checking strategy at every genuine WB retirement:
//     (1) dynamic check against rv32i_ref_model (generic, catches any
//         regression regardless of future program changes)
//     (2) static per-instruction expected-value table (explicit, pinned
//         "golden" values for this specific directed program)
// - Final data-memory content check for all store instructions.
// ============================================================================

`timescale 1ns/1ps

module tb_core;
  import rv32i_pkg::*;
  import ref_model_pkg::*;

  // --------------------------------------------------------------------
  // Clock / reset
  // --------------------------------------------------------------------
  localparam time CLK_PERIOD = 10ns; // 100 MHz (within 100-125 MHz SDC target)
  localparam int  MAX_CYCLES = 500;  // watchdog

  logic clk_i;
  logic rst_ni;

  initial clk_i = 1'b0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  initial begin
    rst_ni = 1'b0;
    repeat (5) @(posedge clk_i);
    rst_ni = 1'b1;
  end

  // --------------------------------------------------------------------
  // DUT interconnect
  // --------------------------------------------------------------------
  logic [XLEN-1:0] imem_addr;
  logic [XLEN-1:0] imem_rdata;
  logic [XLEN-1:0] dmem_addr;
  logic [XLEN-1:0] dmem_wdata;
  logic [XLEN-1:0] dmem_rdata;
  logic [3:0]      dmem_be;
  logic            dmem_we;

  core dut (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .imem_addr_o  (imem_addr),
    .imem_rdata_i (imem_rdata),
    .dmem_addr_o  (dmem_addr),
    .dmem_wdata_o (dmem_wdata),
    .dmem_rdata_i (dmem_rdata),
    .dmem_be_o    (dmem_be),
    .dmem_we_o    (dmem_we)
  );

  // --------------------------------------------------------------------
  // Behavioral instruction memory (combinational read, word-addressed)
  // --------------------------------------------------------------------
  logic [31:0] imem_array [0:1023];

  initial begin
    for (int i = 0; i < 1024; i++) imem_array[i] = 32'h0000_0013; // ADDI x0,x0,0 (NOP) fill
    $readmemh("test_prog.hex", imem_array);
  end

  assign imem_rdata = imem_array[imem_addr[31:2]];

  // --------------------------------------------------------------------
  // Behavioral data memory (combinational read, synchronous byte-enabled
  // write — single-cycle, zero-wait-state per project assumption)
  // --------------------------------------------------------------------
  logic [7:0] dmem_array [0:4095];

  initial for (int i = 0; i < 4096; i++) dmem_array[i] = 8'h00;

  assign dmem_rdata = {dmem_array[dmem_addr+3], dmem_array[dmem_addr+2],
                        dmem_array[dmem_addr+1], dmem_array[dmem_addr]};

  always @(posedge clk_i) begin
    if (dmem_we) begin
      if (dmem_be[0]) dmem_array[dmem_addr]   <= dmem_wdata[7:0];
      if (dmem_be[1]) dmem_array[dmem_addr+1] <= dmem_wdata[15:8];
      if (dmem_be[2]) dmem_array[dmem_addr+2] <= dmem_wdata[23:16];
      if (dmem_be[3]) dmem_array[dmem_addr+3] <= dmem_wdata[31:24];
    end
  end

  // --------------------------------------------------------------------
  // Reference model
  // --------------------------------------------------------------------
  rv32i_ref_model ref_model;

  initial begin
    // Constructed after imem_array is loaded (see retirement-check
    // process below, which waits on reset deassertion first anyway).
  end

  // --------------------------------------------------------------------
  // Static, per-instruction directed expected-value table.
  // check_wr=0 entries are stores/branches: only reg_write==0 is checked.
  // --------------------------------------------------------------------
  typedef struct packed {
    logic        check_wr;
    logic [4:0]  rd;
    logic [31:0] data;
  } exp_t;

  exp_t expected [0:37];

  initial begin
    expected[0]  = '{1'b1, 5'd1,  32'd5};          // addi x1,x0,5
    expected[1]  = '{1'b1, 5'd2,  32'd10};         // addi x2,x0,10
    expected[2]  = '{1'b1, 5'd3,  32'd15};         // add  x3,x1,x2 (fwd)
    expected[3]  = '{1'b1, 5'd4,  32'd5};          // sub  x4,x2,x1
    expected[4]  = '{1'b1, 5'd5,  32'd0};          // and  x5,x1,x2
    expected[5]  = '{1'b1, 5'd6,  32'd15};         // or   x6,x1,x2
    expected[6]  = '{1'b1, 5'd7,  32'd15};         // xor  x7,x1,x2
    expected[7]  = '{1'b1, 5'd8,  32'd1};          // slt  x8,x1,x2
    expected[8]  = '{1'b1, 5'd9,  32'd0};          // sltu x9,x2,x1
    expected[9]  = '{1'b1, 5'd10, 32'd20};         // slli x10,x1,2
    expected[10] = '{1'b1, 5'd11, 32'd5};          // srli x11,x2,1
    expected[11] = '{1'b1, 5'd12, 32'd2};          // srai x12,x1,1
    expected[12] = '{1'b1, 5'd13, 32'h0000_1000};  // lui  x13,0x1
    expected[13] = '{1'b1, 5'd14, 32'd52};         // auipc x14,0x0
    expected[14] = '{1'b1, 5'd15, 32'd100};        // addi x15,x0,100
    expected[15] = '{1'b0, 5'd0,  32'd0};          // sw   x1,0(x15)
    expected[16] = '{1'b0, 5'd0,  32'd0};          // sw   x2,4(x15)
    expected[17] = '{1'b1, 5'd16, 32'd5};          // lw   x16,0(x15)  (load-use)
    expected[18] = '{1'b1, 5'd17, 32'd5};          // add  x17,x16,x0
    expected[19] = '{1'b0, 5'd0,  32'd0};          // sb   x2,8(x15)
    expected[20] = '{1'b1, 5'd18, 32'd10};         // lbu  x18,8(x15)
    expected[21] = '{1'b1, 5'd19, 32'd10};         // lb   x19,8(x15)
    expected[22] = '{1'b0, 5'd0,  32'd0};          // sh   x1,12(x15)
    expected[23] = '{1'b1, 5'd20, 32'd5};          // lh   x20,12(x15)
    expected[24] = '{1'b1, 5'd21, 32'd5};          // lhu  x21,12(x15)
    expected[25] = '{1'b1, 5'd22, 32'd1};          // addi x22,x0,1
    expected[26] = '{1'b0, 5'd0,  32'd0};          // beq  x22,x22,+8 (taken)
    expected[27] = '{1'b1, 5'd23, 32'd42};         // addi x23,x0,42
    expected[28] = '{1'b0, 5'd0,  32'd0};          // bne  x22,x0,+8 (taken)
    expected[29] = '{1'b1, 5'd24, 32'd7};          // addi x24,x0,7
    expected[30] = '{1'b0, 5'd0,  32'd0};          // beq  x22,x0,+8 (not taken)
    expected[31] = '{1'b1, 5'd25, 32'd55};         // addi x25,x0,55
    expected[32] = '{1'b1, 5'd26, 32'd140};        // jal  x26,+8
    expected[33] = '{1'b1, 5'd28, 32'd11};         // addi x28,x0,11
    expected[34] = '{1'b1, 5'd29, 32'd164};        // addi x29,x0,164
    expected[35] = '{1'b1, 5'd30, 32'd156};        // jalr x30,x29,0
    expected[36] = '{1'b1, 5'd31, 32'd77};         // addi x31,x0,77
    expected[37] = '{1'b0, 5'd0,  32'd0};          // jal  x0,0 (halt loop, rd=x0)
  end

  // --------------------------------------------------------------------
  // Retirement monitor + dual checker
  // --------------------------------------------------------------------
  int unsigned retire_count = 0;
  int unsigned error_count  = 0;
  logic [31:0] prev_pc4     = 32'hFFFF_FFFF;
  int unsigned cycle_count  = 0;

  initial begin
    @(posedge rst_ni);
    ref_model = new(imem_array);
  end

  always @(negedge clk_i) begin
    if (rst_ni) begin
      cycle_count++;
      if (cycle_count > MAX_CYCLES) begin
        $error("[TB] Watchdog timeout: halt loop never reached after %0d cycles.", MAX_CYCLES);
        report_summary();
        $finish;
      end

      if (dut.memwb_pc_plus4 != 32'h0) begin
        if (dut.memwb_pc_plus4 == prev_pc4) begin
          $display("[TB] Halt loop detected (PC=0x%0h retiring repeatedly). Ending test.",
                    dut.memwb_pc_plus4 - 4);
          final_memory_check();
          report_summary();
          $finish;
        end else begin
          check_retirement();
        end
        prev_pc4 = dut.memwb_pc_plus4;
      end
    end
  end

  task automatic check_retirement();
    logic [4:0]  ref_rd;
    logic [31:0] ref_data;
    logic        ref_wr;
    logic [31:0] ref_pc;

    logic [4:0]  dut_rd;
    logic [31:0] dut_data;
    logic        dut_wr;

    ref_model.step(ref_rd, ref_data, ref_wr, ref_pc);

    dut_rd   = dut.memwb_rd_addr;
    dut_data = dut.wb_data;
    dut_wr   = dut.memwb_ctrl.reg_write;

    // --- sanity: DUT and reference model must be at the same PC -------
    assert (ref_pc + 32'd4 == dut.memwb_pc_plus4) else begin
      $error("[TB] Retirement #%0d: PC MISMATCH. ref_pc=0x%0h dut_pc+4=0x%0h",
             retire_count, ref_pc, dut.memwb_pc_plus4);
      error_count++;
    end

    // --- dynamic reference-model check ---------------------------------
    assert (dut_wr == ref_wr) else begin
      $error("[TB] Retirement #%0d (PC=0x%0h): reg_write MISMATCH. dut=%0b ref=%0b",
             retire_count, ref_pc, dut_wr, ref_wr);
      error_count++;
    end
    if (ref_wr) begin
      assert (dut_rd == ref_rd) else begin
        $error("[TB] Retirement #%0d (PC=0x%0h): rd MISMATCH. dut=x%0d ref=x%0d",
               retire_count, ref_pc, dut_rd, ref_rd);
        error_count++;
      end
      assert (dut_data == ref_data) else begin
        $error("[TB] Retirement #%0d (PC=0x%0h): data MISMATCH. dut=0x%0h ref=0x%0h",
               retire_count, ref_pc, dut_data, ref_data);
        error_count++;
      end
    end

    // --- static directed-table check -----------------------------------
    if (retire_count <= 37) begin
      if (expected[retire_count].check_wr) begin
        assert (dut_wr && (dut_rd == expected[retire_count].rd) &&
                (dut_data == expected[retire_count].data))
        else begin
          $error("[TB] Retirement #%0d (PC=0x%0h): DIRECTED TABLE MISMATCH. expected x%0d=0x%0h, got wr=%0b rd=x%0d data=0x%0h",
                 retire_count, ref_pc, expected[retire_count].rd, expected[retire_count].data,
                 dut_wr, dut_rd, dut_data);
          error_count++;
        end
      end else begin
        assert (!dut_wr) else begin
          $error("[TB] Retirement #%0d (PC=0x%0h): DIRECTED TABLE MISMATCH. expected no reg_write, got wr=%0b rd=x%0d",
                 retire_count, ref_pc, dut_wr, dut_rd);
          error_count++;
        end
      end
    end

    $display("[TB] Retirement #%0d OK: PC=0x%0h wr=%0b rd=x%0d data=0x%0h",
             retire_count, ref_pc, dut_wr, dut_rd, dut_data);
    retire_count++;
  endtask

  task automatic final_memory_check();
    // Addresses touched: base = x15 = 100
    // 100-103: SW x1 (=5)     108: SB x2 low byte (=10)
    // 104-107: SW x2 (=10)    112-113: SH x1 (=5)
    check_byte(100, 8'd5);   check_byte(101, 8'd0);
    check_byte(102, 8'd0);   check_byte(103, 8'd0);
    check_byte(104, 8'd10);  check_byte(105, 8'd0);
    check_byte(106, 8'd0);   check_byte(107, 8'd0);
    check_byte(108, 8'd10);
    check_byte(112, 8'd5);   check_byte(113, 8'd0);
  endtask

  task automatic check_byte(input int addr, input logic [7:0] exp_val);
    assert (dmem_array[addr] == exp_val) else begin
      $error("[TB] Final DMEM check FAILED at addr %0d: expected 0x%0h, got 0x%0h",
             addr, exp_val, dmem_array[addr]);
      error_count++;
    end
  endtask

  task automatic report_summary();
    $display("========================================================");
    $display("[TB] SUMMARY: %0d instructions retired, %0d error(s)", retire_count, error_count);
    if (error_count == 0) $display("[TB] RESULT: PASS");
    else                  $display("[TB] RESULT: FAIL");
    $display("========================================================");
  endtask

endmodule : tb_core
