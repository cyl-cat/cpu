`timescale 1ns / 1ps
// =============================================================================
// Module   : id2ex
// Function : ID/EX pipeline register. Now carries branch prediction info.
// =============================================================================
`include "riscv_defs.vh"

module id2ex #(
    parameter AW = 32,
    parameter DW = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              flush,
    // Data
    input  wire [AW-1:0]     pc_in,
    input  wire [DW-1:0]     instr_in,
    input  wire [DW-1:0]     rs1_data_in,
    input  wire [DW-1:0]     rs2_data_in,
    input  wire [DW-1:0]     imm_in,
    input  wire [4:0]        rs1_addr_in,
    input  wire [4:0]        rs2_addr_in,
    input  wire [4:0]        rd_addr_in,
    // Control
    input  wire              wr_reg_en_in,
    input  wire              mem_read_in,
    input  wire              mem_write_in,
    input  wire              branch_in,
    input  wire              jump_in,
    input  wire              jump_r_in,
    input  wire              wr_csr_en_in,
    input  wire [AW-1:0]     rd_csr_addr_in,
    input  wire              is_lui_in,
    input  wire              is_auipc_in,
    input  wire              is_fence_in,
    input  wire              is_csr_in,
    // Prediction
    input  wire              predict_taken_in,
    input  wire [AW-1:0]     predict_target_in,
    // Data outputs
    output reg  [AW-1:0]     pc_out,
    output reg  [DW-1:0]     instr_out,
    output reg  [DW-1:0]     rs1_data_out,
    output reg  [DW-1:0]     rs2_data_out,
    output reg  [DW-1:0]     imm_out,
    output reg  [4:0]        rs1_addr_out,
    output reg  [4:0]        rs2_addr_out,
    output reg  [4:0]        rd_addr_out,
    // Control outputs
    output reg               wr_reg_en_out,
    output reg               mem_read_out,
    output reg               mem_write_out,
    output reg               branch_out,
    output reg               jump_out,
    output reg               jump_r_out,
    output reg               wr_csr_en_out,
    output reg  [AW-1:0]     rd_csr_addr_out,
    output reg               is_lui_out,
    output reg               is_auipc_out,
    output reg               is_fence_out,
    output reg               is_csr_out,
    // Prediction outputs
    output reg               predict_taken_out,
    output reg  [AW-1:0]     predict_target_out
);

always @(posedge clk) begin
    if (!rst_n || flush) begin
        pc_out             <= {AW{1'b0}};
        instr_out          <= `INST_NOP;
        rs1_data_out       <= {DW{1'b0}};
        rs2_data_out       <= {DW{1'b0}};
        imm_out            <= {DW{1'b0}};
        rs1_addr_out       <= 5'h0;
        rs2_addr_out       <= 5'h0;
        rd_addr_out        <= 5'h0;
        wr_reg_en_out      <= 1'b0;
        mem_read_out       <= 1'b0;
        mem_write_out      <= 1'b0;
        branch_out         <= 1'b0;
        jump_out           <= 1'b0;
        jump_r_out         <= 1'b0;
        wr_csr_en_out      <= 1'b0;
        rd_csr_addr_out    <= {AW{1'b0}};
        is_lui_out         <= 1'b0;
        is_auipc_out       <= 1'b0;
        is_fence_out       <= 1'b0;
        is_csr_out         <= 1'b0;
        predict_taken_out  <= 1'b0;
        predict_target_out <= {AW{1'b0}};
    end
    else begin
        pc_out             <= pc_in;
        instr_out          <= instr_in;
        rs1_data_out       <= rs1_data_in;
        rs2_data_out       <= rs2_data_in;
        imm_out            <= imm_in;
        rs1_addr_out       <= rs1_addr_in;
        rs2_addr_out       <= rs2_addr_in;
        rd_addr_out        <= rd_addr_in;
        wr_reg_en_out      <= wr_reg_en_in;
        mem_read_out       <= mem_read_in;
        mem_write_out      <= mem_write_in;
        branch_out         <= branch_in;
        jump_out           <= jump_in;
        jump_r_out         <= jump_r_in;
        wr_csr_en_out      <= wr_csr_en_in;
        rd_csr_addr_out    <= rd_csr_addr_in;
        is_lui_out         <= is_lui_in;
        is_auipc_out       <= is_auipc_in;
        is_fence_out       <= is_fence_in;
        is_csr_out         <= is_csr_in;
        predict_taken_out  <= predict_taken_in;
        predict_target_out <= predict_target_in;
    end
end

endmodule
