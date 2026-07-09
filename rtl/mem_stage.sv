// ============================================================================
// mem_stage.sv
// MEM stage: data memory address/byte-enable/write-data generation for
// stores, and byte/halfword extraction + sign/zero extension for loads.
// Data memory modeled as single-cycle, zero-wait-state, full-word read with
// byte-write-enable support (per project memory-interface assumption).
// ============================================================================

module mem_stage
  import rv32i_pkg::*;
(
  input  logic [XLEN-1:0] alu_result_i,  // memory address
  input  logic [XLEN-1:0] store_data_i,  // rs2 data (forwarded), unaligned
  input  ctrl_t            ctrl_i,

  output logic [XLEN-1:0] dmem_addr_o,
  output logic [XLEN-1:0] dmem_wdata_o,
  output logic [3:0]      dmem_be_o,
  output logic            dmem_we_o,
  input  logic [XLEN-1:0] dmem_rdata_i,

  output logic [XLEN-1:0] mem_rdata_o    // sign/zero-extended load result
);

  assign dmem_addr_o = alu_result_i;
  assign dmem_we_o    = ctrl_i.mem_write;

  // ------------------------------------------------------------------
  // Store path: byte-lane placement + byte-enable generation
  // ------------------------------------------------------------------
  always_comb begin
    dmem_be_o    = 4'b0000;
    dmem_wdata_o = '0;
    if (ctrl_i.mem_write) begin
      unique case (ctrl_i.mem_size)
        MEM_SIZE_BYTE: begin
          unique case (alu_result_i[1:0])
            2'b00: begin dmem_be_o = 4'b0001; dmem_wdata_o = {24'b0, store_data_i[7:0]}; end
            2'b01: begin dmem_be_o = 4'b0010; dmem_wdata_o = {16'b0, store_data_i[7:0], 8'b0}; end
            2'b10: begin dmem_be_o = 4'b0100; dmem_wdata_o = {8'b0, store_data_i[7:0], 16'b0}; end
            2'b11: begin dmem_be_o = 4'b1000; dmem_wdata_o = {store_data_i[7:0], 24'b0}; end
          endcase
        end
        MEM_SIZE_HALF: begin
          unique case (alu_result_i[1])
            1'b0: begin dmem_be_o = 4'b0011; dmem_wdata_o = {16'b0, store_data_i[15:0]}; end
            1'b1: begin dmem_be_o = 4'b1100; dmem_wdata_o = {store_data_i[15:0], 16'b0}; end
          endcase
        end
        default: begin // WORD
          dmem_be_o    = 4'b1111;
          dmem_wdata_o = store_data_i;
        end
      endcase
    end
  end

  // ------------------------------------------------------------------
  // Load path: byte-lane extraction + sign/zero extension
  // ------------------------------------------------------------------
  always_comb begin
    mem_rdata_o = dmem_rdata_i;
    if (ctrl_i.mem_read) begin
      unique case (ctrl_i.mem_size)
        MEM_SIZE_BYTE: begin
          unique case (alu_result_i[1:0])
            2'b00: mem_rdata_o = {{24{dmem_rdata_i[7]}},  dmem_rdata_i[7:0]};
            2'b01: mem_rdata_o = {{24{dmem_rdata_i[15]}}, dmem_rdata_i[15:8]};
            2'b10: mem_rdata_o = {{24{dmem_rdata_i[23]}}, dmem_rdata_i[23:16]};
            2'b11: mem_rdata_o = {{24{dmem_rdata_i[31]}}, dmem_rdata_i[31:24]};
          endcase
        end
        MEM_SIZE_BYTE_U: begin
          unique case (alu_result_i[1:0])
            2'b00: mem_rdata_o = {24'b0, dmem_rdata_i[7:0]};
            2'b01: mem_rdata_o = {24'b0, dmem_rdata_i[15:8]};
            2'b10: mem_rdata_o = {24'b0, dmem_rdata_i[23:16]};
            2'b11: mem_rdata_o = {24'b0, dmem_rdata_i[31:24]};
          endcase
        end
        MEM_SIZE_HALF: begin
          unique case (alu_result_i[1])
            1'b0: mem_rdata_o = {{16{dmem_rdata_i[15]}}, dmem_rdata_i[15:0]};
            1'b1: mem_rdata_o = {{16{dmem_rdata_i[31]}}, dmem_rdata_i[31:16]};
          endcase
        end
        MEM_SIZE_HALF_U: begin
          unique case (alu_result_i[1])
            1'b0: mem_rdata_o = {16'b0, dmem_rdata_i[15:0]};
            1'b1: mem_rdata_o = {16'b0, dmem_rdata_i[31:16]};
          endcase
        end
        default: mem_rdata_o = dmem_rdata_i; // WORD
      endcase
    end
  end

endmodule : mem_stage
