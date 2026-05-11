`timescale 1ns / 1ps
// =============================================================================
// Module   : mem2wb
// Function : MEM/WB pipeline register. Captures writeback data and control.
// =============================================================================

module mem2wb #(
    parameter AW = 32,
    parameter DW = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    // Data
    input  wire [DW-1:0]     wr_reg_data_in, // final writeback data
    input  wire [4:0]        rd_addr_in,
    // Control
    input  wire              wr_reg_en_in,
    // Outputs (to WB / register file / forwarding)
    output reg  [DW-1:0]     wr_reg_data_out,
    output reg  [4:0]        rd_addr_out,
    output reg               wr_reg_en_out
);

always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
        wr_reg_data_out <= {DW{1'b0}};
        rd_addr_out     <= 5'h0;
        wr_reg_en_out   <= 1'b0;
    end
    else begin
        wr_reg_data_out <= wr_reg_data_in;
        rd_addr_out     <= rd_addr_in;
        wr_reg_en_out   <= wr_reg_en_in;
    end

endmodule
