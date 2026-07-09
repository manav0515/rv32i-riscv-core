// ============================================================================
// rv32i_ref_model.sv
//
// Lightweight, purely behavioral RV32I reference model used by tb_core.sv.
// Executes instructions strictly in true architectural program order
// (branches/jumps taken exactly per the ISA spec), independent of the DUT's
// pipeline timing. Because it walks the SAME instruction image in true
// program order, its Nth "step()" call produces exactly the architectural
// effect of the DUT's Nth genuine (non-bubble) WB retirement — the two
// sequences line up 1:1 regardless of pipeline stalls/flushes on the DUT
// side, since those never change program order, only its timing.
//
// Scope matches the DUT exactly: base RV32I integer ops only, no CSR/M/A/F/
// D/C, no exceptions/interrupts (per project ISA scope).
// ============================================================================

package ref_model_pkg;
  import rv32i_pkg::*;

  class rv32i_ref_model;

    logic [31:0] regs [0:31];
    logic [7:0]  dmem [int];          // sparse byte-addressable memory
    logic [31:0] imem [0:1023];       // word-addressed instruction image
    logic [31:0] pc;

    function new(logic [31:0] imem_img [0:1023]);
      imem = imem_img;
      for (int i = 0; i < 32; i++) regs[i] = '0;
      pc = 32'h0;
    endfunction

    function logic [7:0] dmem_byte(input logic [31:0] addr);
      if (dmem.exists(int'(addr))) return dmem[int'(addr)];
      else return 8'h00;
    endfunction

    // ----------------------------------------------------------------
    // Execute exactly one architectural instruction at the model's
    // current `pc`. Returns the committed register-write effect (if
    // any) so tb_core.sv can compare it against the DUT's retiring
    // WB-stage output for the same instruction.
    // ----------------------------------------------------------------
    function void step(output logic [4:0]  rd_addr,
                        output logic [31:0] rd_data,
                        output logic        reg_write,
                        output logic [31:0] retired_pc);
      logic [31:0] instr;
      logic [6:0]  opcode;
      logic [2:0]  funct3;
      logic        funct7b5;
      logic [4:0]  rs1, rs2, rd;
      logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
      logic [31:0] rs1_v, rs2_v, alu_r;
      logic [31:0] next_pc;
      logic        wr_en;
      logic [31:0] wr_val;

      retired_pc = pc;
      instr      = imem[pc >> 2];

      opcode   = instr[6:0];
      rd       = instr[11:7];
      funct3   = instr[14:12];
      rs1      = instr[19:15];
      rs2      = instr[24:20];
      funct7b5 = instr[30];

      imm_i = {{20{instr[31]}}, instr[31:20]};
      imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
      imm_u = {instr[31:12], 12'b0};
      imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

      rs1_v = (rs1 == 0) ? 32'b0 : regs[rs1];
      rs2_v = (rs2 == 0) ? 32'b0 : regs[rs2];

      wr_en   = 1'b0;
      wr_val  = '0;
      alu_r   = '0;
      next_pc = pc + 32'd4;

      unique case (opcode)

        OPCODE_R_TYPE: begin
          wr_en = 1'b1;
          unique case (funct3)
            3'b000:  alu_r = funct7b5 ? (rs1_v - rs2_v) : (rs1_v + rs2_v);
            3'b001:  alu_r = rs1_v << rs2_v[4:0];
            3'b010:  alu_r = ($signed(rs1_v) < $signed(rs2_v)) ? 32'd1 : 32'd0;
            3'b011:  alu_r = (rs1_v < rs2_v) ? 32'd1 : 32'd0;
            3'b100:  alu_r = rs1_v ^ rs2_v;
            3'b101:  alu_r = funct7b5 ? ($signed(rs1_v) >>> rs2_v[4:0]) : (rs1_v >> rs2_v[4:0]);
            3'b110:  alu_r = rs1_v | rs2_v;
            3'b111:  alu_r = rs1_v & rs2_v;
            default: alu_r = '0;
          endcase
          wr_val = alu_r;
        end

        OPCODE_I_ALU: begin
          wr_en = 1'b1;
          unique case (funct3)
            3'b000:  alu_r = rs1_v + imm_i;
            3'b001:  alu_r = rs1_v << imm_i[4:0];
            3'b010:  alu_r = ($signed(rs1_v) < $signed(imm_i)) ? 32'd1 : 32'd0;
            3'b011:  alu_r = (rs1_v < imm_i) ? 32'd1 : 32'd0;
            3'b100:  alu_r = rs1_v ^ imm_i;
            3'b101:  alu_r = funct7b5 ? ($signed(rs1_v) >>> imm_i[4:0]) : (rs1_v >> imm_i[4:0]);
            3'b110:  alu_r = rs1_v | imm_i;
            3'b111:  alu_r = rs1_v & imm_i;
            default: alu_r = '0;
          endcase
          wr_val = alu_r;
        end

        OPCODE_LOAD: begin
          logic [31:0] addr;
          logic [31:0] ld;
          addr   = rs1_v + imm_i;
          ld     = {dmem_byte(addr+3), dmem_byte(addr+2), dmem_byte(addr+1), dmem_byte(addr)};
          wr_en  = 1'b1;
          unique case (funct3)
            3'b000:  wr_val = {{24{ld[7]}},  ld[7:0]};   // LB
            3'b001:  wr_val = {{16{ld[15]}}, ld[15:0]};  // LH
            3'b010:  wr_val = ld;                        // LW
            3'b100:  wr_val = {24'b0, ld[7:0]};          // LBU
            3'b101:  wr_val = {16'b0, ld[15:0]};         // LHU
            default: wr_val = ld;
          endcase
        end

        OPCODE_STORE: begin
          logic [31:0] addr;
          addr = rs1_v + imm_s;
          unique case (funct3)
            3'b000: dmem[int'(addr)] = rs2_v[7:0];                                   // SB
            3'b001: begin
              dmem[int'(addr)]   = rs2_v[7:0];
              dmem[int'(addr+1)] = rs2_v[15:8];
            end // SH
            3'b010: begin
              dmem[int'(addr)]   = rs2_v[7:0];
              dmem[int'(addr+1)] = rs2_v[15:8];
              dmem[int'(addr+2)] = rs2_v[23:16];
              dmem[int'(addr+3)] = rs2_v[31:24];
            end // SW
            default: ;
          endcase
        end

        OPCODE_BRANCH: begin
          logic taken;
          unique case (funct3)
            3'b000:  taken = (rs1_v == rs2_v);              // BEQ
            3'b001:  taken = (rs1_v != rs2_v);               // BNE
            3'b100:  taken = ($signed(rs1_v) <  $signed(rs2_v)); // BLT
            3'b101:  taken = ($signed(rs1_v) >= $signed(rs2_v)); // BGE
            3'b110:  taken = (rs1_v < rs2_v);                // BLTU
            3'b111:  taken = (rs1_v >= rs2_v);               // BGEU
            default: taken = 1'b0;
          endcase
          if (taken) next_pc = pc + imm_b;
        end

        OPCODE_JAL: begin
          wr_en   = 1'b1;
          wr_val  = pc + 32'd4;
          next_pc = pc + imm_j;
        end

        OPCODE_JALR: begin
          wr_en   = 1'b1;
          wr_val  = pc + 32'd4;
         next_pc = (rs1_v + imm_i) & 32'hFFFF_FFFE;
        end

        OPCODE_LUI: begin
          wr_en  = 1'b1;
          wr_val = imm_u;
        end

        OPCODE_AUIPC: begin
          wr_en  = 1'b1;
          wr_val = pc + imm_u;
        end

        default: ; // unsupported/illegal opcode: no architectural effect (matches RTL)
      endcase

      if (wr_en && (rd != 0)) begin
        regs[rd] = wr_val;
      end

      rd_addr   = rd;
      rd_data   = wr_val;
      reg_write = wr_en && (rd != 0);
      pc        = next_pc;
    endfunction

  endclass

endpackage : ref_model_pkg
