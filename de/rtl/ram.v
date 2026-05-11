`timescale 1ns / 1ps
`include "riscv_defs.vh"

module ram #(
    parameter string FILE = "rv32ui-p-addi.dat",
    parameter AW   = 32,
    parameter DW   = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              wr_en,
    input  wire [3:0]        wr_be,
    input  wire [AW-1:0]     wr_addr,
    input  wire [DW-1:0]     wr_data,
    input  wire [AW-1:0]     rd_addr,
    output wire [DW-1:0]     rd_data
);

reg [DW-1:0] ram_mem [0:`RAM_DEPTH-1];

wire [AW-1:2] waddr = wr_addr[AW-1:2];
wire [AW-1:2] raddr = rd_addr[AW-1:2];

integer i;

initial begin
    string init_file;
    init_file = FILE;
    void'($value$plusargs("TEST_FILE=%s", init_file));

    for (i = 0; i < `RAM_DEPTH; i = i + 1)
        ram_mem[i] = {DW{1'b0}};

    if (init_file != "")
        $readmemh(init_file, ram_mem);
    else
        $error("ram FILE is empty and +TEST_FILE was not provided");
end

always @(posedge clk) begin
    if (wr_en) begin
        if (wr_be[0]) ram_mem[waddr][7:0]   <= wr_data[7:0];
        if (wr_be[1]) ram_mem[waddr][15:8]  <= wr_data[15:8];
        if (wr_be[2]) ram_mem[waddr][23:16] <= wr_data[23:16];
        if (wr_be[3]) ram_mem[waddr][31:24] <= wr_data[31:24];
    end
end

assign rd_data = ram_mem[raddr];

endmodule
