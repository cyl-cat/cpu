`timescale 1ns / 1ps
// =============================================================================
// Module   : forwarding_unit
// Function : 5-stage pipeline data forwarding (bypass) network.
//
//   Detects RAW data hazards and selects the most recent value:
//     Priority 1: EX/MEM -> EX  (forward_x = 2'b10)
//       The instruction in MEM stage wrote to a register that the
//       instruction in EX stage needs. Forward the ALU/EX result.
//     Priority 2: MEM/WB -> EX  (forward_x = 2'b01)
//       The instruction in WB stage wrote to a register that the
//       instruction in EX stage needs. Forward the WB data.
//     Default:    No forward    (forward_x = 2'b00)
//       Use the register file value from ID stage.
// =============================================================================

module forwarding_unit (
    // EX stage source registers (from ID/EX register)
    input  wire [4:0]    ex_rs1_addr,
    input  wire [4:0]    ex_rs2_addr,
    // MEM stage (from EX/MEM register)
    input  wire          mem_wr_reg_en,
    input  wire [4:0]    mem_rd_addr,
    // WB stage (from MEM/WB register)
    input  wire          wb_wr_reg_en,
    input  wire [4:0]    wb_rd_addr,
    // Forwarding control
    output reg  [1:0]    forward_a,      // select for rs1
    output reg  [1:0]    forward_b       // select for rs2
);

localparam FWD_NONE    = 2'b00;   // use register file value
localparam FWD_FROM_WB = 2'b01;   // forward from MEM/WB stage
localparam FWD_FROM_MEM= 2'b10;   // forward from EX/MEM stage

// Forward A (rs1)
always @(*) begin
    if (mem_wr_reg_en && (mem_rd_addr != 5'h0) &&
        (mem_rd_addr == ex_rs1_addr))
        forward_a = FWD_FROM_MEM;
    else if (wb_wr_reg_en && (wb_rd_addr != 5'h0) &&
             (wb_rd_addr == ex_rs1_addr))
        forward_a = FWD_FROM_WB;
    else
        forward_a = FWD_NONE;
end

// Forward B (rs2)
always @(*) begin
    if (mem_wr_reg_en && (mem_rd_addr != 5'h0) &&
        (mem_rd_addr == ex_rs2_addr))
        forward_b = FWD_FROM_MEM;
    else if (wb_wr_reg_en && (wb_rd_addr != 5'h0) &&
             (wb_rd_addr == ex_rs2_addr))
        forward_b = FWD_FROM_WB;
    else
        forward_b = FWD_NONE;
end

endmodule
