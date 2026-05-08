`timescale 1ns / 1ps
`include "riscv_defs.vh"

module rom #(
    parameter string FILE = "rv32ui-p-addi.dat",
    parameter AW   = 32,
    parameter DW   = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              update_en,
    input  wire              instr_wr_en,
    input  wire [AW-1:0]     instr_wr_addr,
    input  wire [DW-1:0]     instr_wr_data,
    input  wire [AW-1:0]     instr_addr,
    output wire [DW-1:0]     instr_out
);

function integer clogb2 (input integer bit_depth);
begin
    for (clogb2 = 0; bit_depth > 0; clogb2 = clogb2 + 1)
        bit_depth = bit_depth >> 1;
end
endfunction

localparam RATIO = DW / 8;
localparam EX    = clogb2(RATIO) - 1;

reg [DW-1:0] rom_mem [0:`ROM_DEPTH-1];

// initial begin
//     $readmemh(FILE, rom_mem);
// end

// 仅保留在线更新写口
always @(posedge clk) begin
    if (update_en && instr_wr_en)
        rom_mem[instr_wr_addr[AW-1:EX]] <= instr_wr_data;
end

// 组合读：PC 与指令同拍对齐
assign instr_out =
    (!rst_n || update_en) ? {DW{1'b0}} :
    rom_mem[instr_addr[AW-1:EX]];

endmodule
