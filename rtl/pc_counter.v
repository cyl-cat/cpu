`timescale 1ns / 1ps
// =============================================================================
// Module   : pc_counter
// Function : PC for 5-stage pipeline with BHT/BTB prediction.
//   Next-PC priority:
//     1. Redirect from pipeline controller (mispredict / interrupt)
//     2. Stall (hold current PC)
//     3. BHT+BTB predict taken → use BTB target
//     4. Default: PC + 4
// =============================================================================
module pc_counter #(
    parameter AW = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              rom_update_en,
    // Pipeline controller
    input  wire              pc_stall,
    input  wire              pc_jump,
    input  wire [AW-1:0]     pc_jump_addr,
    // BHT/BTB prediction
    input  wire              predict_taken,   // BHT says taken AND BTB hit
    input  wire [AW-1:0]     predict_target,  // BTB target
    // Output
    output reg  [AW-1:0]     pc_out
);

always @(posedge clk) begin
    if (!rst_n)
        pc_out <= {AW{1'b0}};
    else if (rom_update_en)
        pc_out <= {AW{1'b0}};
    else if (pc_jump)
        pc_out <= pc_jump_addr;
    else if (pc_stall)
        pc_out <= pc_out;
    else if (predict_taken)
        pc_out <= predict_target;
    else
        pc_out <= pc_out + 32'h4;
end

endmodule
