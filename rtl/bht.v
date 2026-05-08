`timescale 1ns / 1ps

module bht #(
    parameter BHT_AW = 6
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] if_pc,
    output wire        predict_taken,
    input  wire        update_en,
    input  wire [31:0] update_pc,
    input  wire        actual_taken
);

localparam NUM_ENTRIES = 1 << BHT_AW;

(* ram_style = "distributed" *)
reg [1:0] bht_table [0:NUM_ENTRIES-1];

wire [BHT_AW-1:0] if_index     = if_pc[BHT_AW+1:2];
wire [BHT_AW-1:0] update_index = update_pc[BHT_AW+1:2];

wire [1:0] current_val = bht_table[update_index];
wire [1:0] next_val =
    actual_taken ? ((current_val == 2'b11) ? 2'b11 : current_val + 2'b01) :
                   ((current_val == 2'b00) ? 2'b00 : current_val - 2'b01);

assign predict_taken = bht_table[if_index][1];

integer i;
initial begin
    for (i = 0; i < NUM_ENTRIES; i = i + 1)
        bht_table[i] = 2'b01;   // weakly not taken
end

always @(posedge clk) begin
    if (update_en)
        bht_table[update_index] <= next_val;
end

endmodule