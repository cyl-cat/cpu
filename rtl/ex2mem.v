`timescale 1ns / 1ps
// =============================================================================
// Module   : ex2mem
// Function : EX/MEM pipeline register. Captures ALU result, store data,
//            destination register, and control signals for MEM and WB stages.
// =============================================================================
`include "riscv_defs.vh"

module ex2mem #(
    parameter AW = 32,
    parameter DW = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              flush,
    // Data
    input  wire [AW-1:0]     pc_in,
    input  wire [DW-1:0]     instr_in,
    input  wire [DW-1:0]     alu_result_in,
    input  wire [DW-1:0]     wr_reg_data_in,   // computed rd data (non-load)
    input  wire [DW-1:0]     mem_wr_data_in,    // rs2 data for store
    input  wire [4:0]        rd_addr_in,
    // Control
    input  wire              wr_reg_en_in,
    input  wire              mem_read_in,
    input  wire              mem_write_in,
    input  wire              wr_csr_en_in,
    input  wire [AW-1:0]     csr_wr_addr_in,
    input  wire [DW-1:0]     csr_wr_data_in,
    // Outputs
    output reg  [AW-1:0]     pc_out,
    output reg  [DW-1:0]     instr_out,
    output reg  [DW-1:0]     alu_result_out,
    output reg  [DW-1:0]     wr_reg_data_out,
    output reg  [DW-1:0]     mem_wr_data_out,
    output reg  [4:0]        rd_addr_out,
    output reg               wr_reg_en_out,
    output reg               mem_read_out,
    output reg               mem_write_out,
    output reg               wr_csr_en_out,
    output reg  [AW-1:0]     csr_wr_addr_out,
    output reg  [DW-1:0]     csr_wr_data_out
);

always @(posedge clk or negedge rst_n)
    if (!rst_n || flush) begin
        pc_out          <= {AW{1'b0}};
        instr_out       <= `INST_NOP;
        alu_result_out  <= {DW{1'b0}};
        wr_reg_data_out <= {DW{1'b0}};
        mem_wr_data_out <= {DW{1'b0}};
        rd_addr_out     <= 5'h0;
        wr_reg_en_out   <= 1'b0;
        mem_read_out    <= 1'b0;
        mem_write_out   <= 1'b0;
        wr_csr_en_out   <= 1'b0;
        csr_wr_addr_out <= {AW{1'b0}};
        csr_wr_data_out <= {DW{1'b0}};
    end
    else begin
        pc_out          <= pc_in;
        instr_out       <= instr_in;
        alu_result_out  <= alu_result_in;
        wr_reg_data_out <= wr_reg_data_in;
        mem_wr_data_out <= mem_wr_data_in;
        rd_addr_out     <= rd_addr_in;
        wr_reg_en_out   <= wr_reg_en_in;
        mem_read_out    <= mem_read_in;
        mem_write_out   <= mem_write_in;
        wr_csr_en_out   <= wr_csr_en_in;
        csr_wr_addr_out <= csr_wr_addr_in;
        csr_wr_data_out <= csr_wr_data_in;
    end

endmodule
