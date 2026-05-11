`timescale 1ns / 1ps
// =============================================================================
// Module   : mem_stage
// Function : Memory access stage for 5-stage pipeline (combinational).
//            - Generates RAM read/write address and data
//            - Handles sub-word store (SB/SH) read-modify-write
//            - Handles sub-word load (LB/LH/LBU/LHU) sign/zero extension
//            - Selects final writeback data (ALU result vs memory data)
// =============================================================================
`include "riscv_defs.vh"

module mem_stage #(
    parameter AW = 32,
    parameter DW = 32
)(
    // From EX/MEM register
    input  wire [DW-1:0]     instr,
    input  wire [DW-1:0]     alu_result,     // effective address for load/store
    input  wire [DW-1:0]     wr_reg_data_in, // non-load writeback data
    input  wire [DW-1:0]     mem_wr_data_in, // rs2 data for store
    input  wire              mem_read,
    input  wire              mem_write,
    // RAM interface
    output wire [AW-1:0]     ram_rd_addr,
    input  wire [DW-1:0]     ram_rd_data,
    output reg               ram_wr_en,
    output wire [AW-1:0]     ram_wr_addr,
    output reg  [DW-1:0]     ram_wr_data,
    // Output to MEM/WB
    output reg  [DW-1:0]     mem_rd_data,    // loaded data (after extension)
    output reg  [DW-1:0]     wr_reg_data_out, // final writeback data
    output reg [3:0] ram_wr_be
);

wire [2:0] func3 = instr[14:12];

assign ram_rd_addr = alu_result;
assign ram_wr_addr = alu_result;

// Store data generation (sub-word read-modify-write)
always @(*) begin
    ram_wr_en   = mem_write;
    ram_wr_be   = 4'b0000;
    ram_wr_data = 32'h00000000;

    if (mem_write) begin
        case (func3)
            `INST_SB: begin
                case (alu_result[1:0])
                    2'b00: begin ram_wr_be = 4'b0001; ram_wr_data = {24'h0, mem_wr_data_in[7:0]}; end
                    2'b01: begin ram_wr_be = 4'b0010; ram_wr_data = {16'h0, mem_wr_data_in[7:0], 8'h0}; end
                    2'b10: begin ram_wr_be = 4'b0100; ram_wr_data = {8'h0, mem_wr_data_in[7:0], 16'h0}; end
                    2'b11: begin ram_wr_be = 4'b1000; ram_wr_data = {mem_wr_data_in[7:0], 24'h0}; end
                endcase
            end
            `INST_SH: begin
                if (alu_result[1] == 1'b0) begin
                    ram_wr_be   = 4'b0011;
                    ram_wr_data = {16'h0, mem_wr_data_in[15:0]};
                end else begin
                    ram_wr_be   = 4'b1100;
                    ram_wr_data = {mem_wr_data_in[15:0], 16'h0};
                end
            end
            `INST_SW: begin
                ram_wr_be   = 4'b1111;
                ram_wr_data = mem_wr_data_in;
            end
            default: begin
                ram_wr_en   = 1'b0;
                ram_wr_be   = 4'b0000;
                ram_wr_data = 32'h0;
            end
        endcase
    end
end

// Load data extraction (sub-word sign/zero extension)
always @(*) begin
    mem_rd_data = ram_rd_data;
    if (mem_read) begin
        case (func3)
            `INST_LB: begin
                case (alu_result[1:0])
                    2'b00:   mem_rd_data = {{24{ram_rd_data[7]}},  ram_rd_data[7:0]};
                    2'b01:   mem_rd_data = {{24{ram_rd_data[15]}}, ram_rd_data[15:8]};
                    2'b10:   mem_rd_data = {{24{ram_rd_data[23]}}, ram_rd_data[23:16]};
                    2'b11:   mem_rd_data = {{24{ram_rd_data[31]}}, ram_rd_data[31:24]};
                    default: mem_rd_data = {{24{ram_rd_data[7]}},  ram_rd_data[7:0]};
                endcase
            end
            `INST_LH: begin
                case (alu_result[1])
                    1'b0:    mem_rd_data = {{16{ram_rd_data[15]}}, ram_rd_data[15:0]};
                    1'b1:    mem_rd_data = {{16{ram_rd_data[31]}}, ram_rd_data[31:16]};
                    default: mem_rd_data = {{16{ram_rd_data[15]}}, ram_rd_data[15:0]};
                endcase
            end
            `INST_LW:
                mem_rd_data = ram_rd_data;
            `INST_LBU: begin
                case (alu_result[1:0])
                    2'b00:   mem_rd_data = {24'h0, ram_rd_data[7:0]};
                    2'b01:   mem_rd_data = {24'h0, ram_rd_data[15:8]};
                    2'b10:   mem_rd_data = {24'h0, ram_rd_data[23:16]};
                    2'b11:   mem_rd_data = {24'h0, ram_rd_data[31:24]};
                    default: mem_rd_data = {24'h0, ram_rd_data[7:0]};
                endcase
            end
            `INST_LHU: begin
                case (alu_result[1])
                    1'b0:    mem_rd_data = {16'h0, ram_rd_data[15:0]};
                    1'b1:    mem_rd_data = {16'h0, ram_rd_data[31:16]};
                    default: mem_rd_data = {16'h0, ram_rd_data[15:0]};
                endcase
            end
            default:
                mem_rd_data = ram_rd_data;
        endcase
    end
end

// Writeback data selection: load data or ALU/other result
always @(*) begin
    if (mem_read)
        wr_reg_data_out = mem_rd_data;
    else
        wr_reg_data_out = wr_reg_data_in;
end

endmodule
