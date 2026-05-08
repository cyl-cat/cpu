`timescale 1ns / 1ps
// =============================================================================
// Module   : register_file
// Function : 32x32-bit register file with 2 read ports and 1 write port.
//            Includes combinational bypass: if WB writes the same register
//            being read, the write data is forwarded immediately.
//            x0 is hardwired to zero.
// =============================================================================
module register_file #(
    parameter DW = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    // Read ports (ID stage)
    input  wire [4:0]        rd_rs1_addr,
    input  wire [4:0]        rd_rs2_addr,
    output reg  [DW-1:0]     rd_rs1_data,
    output reg  [DW-1:0]     rd_rs2_data,
    // Write port (WB stage)
    input  wire              wr_en,
    input  wire [4:0]        wr_addr,
    input  wire [DW-1:0]     wr_data,
    // Debug / test outputs
    output wire [DW-1:0]     test_case,
    output wire [DW-1:0]     reg_s10,
    output wire [DW-1:0]     reg_s11
);

reg [DW-1:0] regs [0:31];

assign test_case = regs[3];
assign reg_s10   = regs[26];
assign reg_s11   = regs[27];

// Read port 1 with WB bypass
always @(*) begin
    if (rd_rs1_addr == 5'h0)
        rd_rs1_data = {DW{1'b0}};
    else if (wr_en && (rd_rs1_addr == wr_addr))
        rd_rs1_data = wr_data;
    else
        rd_rs1_data = regs[rd_rs1_addr];
end

// Read port 2 with WB bypass
always @(*) begin
    if (rd_rs2_addr == 5'h0)
        rd_rs2_data = {DW{1'b0}};
    else if (wr_en && (rd_rs2_addr == wr_addr))
        rd_rs2_data = wr_data;
    else
        rd_rs2_data = regs[rd_rs2_addr];
end

// Write port (WB stage drives this)
integer i;
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] <= {DW{1'b0}};
    end
    else if (wr_en && (wr_addr != 5'h0))
        regs[wr_addr] <= wr_data;

endmodule
