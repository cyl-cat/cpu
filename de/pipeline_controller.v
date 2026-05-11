`timescale 1ns / 1ps
// =============================================================================
// Module   : pipeline_controller
// Function : Unified pipeline control for 5-stage pipeline with BHT/BTB.
//
//   With dynamic prediction, flush is only needed on MISPREDICTION:
//     - Predicted taken, actual not-taken → flush, redirect to PC+4
//     - Predicted not-taken, actual taken → flush, redirect to branch target
//     - Prediction correct → NO flush (0-cycle effective penalty)
//
//   Priority:
//     1. Interrupt          → flush IF/ID + ID/EX + EX/MEM, redirect PC
//     2. Misprediction      → flush IF/ID + ID/EX, redirect PC
//     3. Jump (JAL/JALR)*   → flush IF/ID + ID/EX, redirect PC
//     4. Load-use stall     → stall PC + IF/ID, flush ID/EX
//     5. Normal             → no action
//
//   * Note: JAL could be predicted by BTB in IF. If BTB hits with correct
//     target, no flush needed. JALR target depends on rs1, so BTB may miss.
//     For simplicity, we treat jump mispredictions like branch mispredictions.
// =============================================================================

module pipeline_controller #(
    parameter AW = 32
)(
    // From EX stage: actual branch/jump outcome
    input  wire              ex_branch,          // is a branch instruction
    input  wire              ex_branch_taken,     // actual branch taken
    input  wire [AW-1:0]     ex_branch_target,    // actual target address
    input  wire              ex_jump,             // is JAL/JALR
    input  wire              ex_jump_r,           // is JALR (not predictable)
    input  wire [AW-1:0]     ex_pc,               // PC of branch/jump instr
    // From ID/EX: prediction that was made
    input  wire              ex_predict_taken,     // what IF predicted
    input  wire [AW-1:0]     ex_predict_target,    // predicted target
    // Interrupt
    input  wire              int_en,
    input  wire [AW-1:0]     int_addr,
    // Hazard
    input  wire              load_use_stall,
    input  wire              branch_wait_stall,

    input  wire              id_jal_early,
    input  wire [AW-1:0]     id_jal_target,
    // Outputs
    output reg               pc_stall,
    output reg               pc_jump,
    output reg  [AW-1:0]     pc_jump_addr,
    output reg               ifid_stall,
    output reg               ifid_flush,
    output reg               idex_flush,
    output reg               exmem_flush,
    // BHT/BTB update signals
    output wire              bht_update_en,
    output wire [AW-1:0]     bht_update_pc,
    output wire              bht_actual_taken,
    output wire              btb_update_en,
    output wire [AW-1:0]     btb_update_pc,
    output wire [AW-1:0]     btb_update_target,
    output wire              btb_update_taken
);

// Misprediction detection
wire branch_mispredicted;
wire jump_needs_flush;

// Branch: compare predicted vs actual
//   Mispredict case 1: predicted taken, actual not-taken
//   Mispredict case 2: predicted not-taken, actual taken
//   Mispredict case 3: predicted taken with wrong target
assign branch_mispredicted = ex_branch && (
    (ex_predict_taken != ex_branch_taken) ||
    (ex_predict_taken && ex_branch_taken && (ex_predict_target != ex_branch_target))
);

// Jump: JAL could be predicted by BTB. Flush if prediction was wrong.
// JALR is hard to predict (rs1-dependent), flush unless BTB got it right.
assign jump_needs_flush = ex_jump && (
    (!ex_predict_taken) ||                    // wasn't predicted taken
    (ex_predict_target != ex_branch_target)   // wrong target
);

// Correct redirect address on misprediction
wire [AW-1:0] correct_addr;
assign correct_addr = (ex_branch && !ex_branch_taken) ? (ex_pc + 32'h4) :
                      ex_branch_target;

// BHT update: for every branch instruction
assign bht_update_en = ex_branch & (~int_en);
assign bht_update_pc   = ex_pc;
assign bht_actual_taken = ex_branch_taken;

// BTB update: for branches and jumps
assign btb_update_en =
    (ex_branch | (ex_jump & ~ex_jump_r)) & (~int_en);
assign btb_update_pc     = ex_pc;
assign btb_update_target = ex_branch_target;
assign btb_update_taken  = ex_branch_taken | (ex_jump & ~ex_jump_r);

// Control signal generation
always @(*) begin
    pc_stall     = 1'b0;
    pc_jump      = 1'b0;
    pc_jump_addr = {AW{1'b0}};
    ifid_stall   = 1'b0;
    ifid_flush   = 1'b0;
    idex_flush   = 1'b0;
    exmem_flush  = 1'b0;

    if (int_en) begin
        // Priority 1: Interrupt
        pc_jump      = 1'b1;
        pc_jump_addr = int_addr;
        ifid_flush   = 1'b1;
        idex_flush   = 1'b1;
        exmem_flush  = 1'b1;
    end
    else if (branch_mispredicted) begin
        // Priority 2: Older EX-stage branch redirect must beat younger ID-stage early jump
        pc_jump      = 1'b1;
        pc_jump_addr = correct_addr;
        ifid_flush   = 1'b1;
        idex_flush   = 1'b1;
    end
    else if (jump_needs_flush) begin
        // Priority 3: Older EX-stage JAL/JALR redirect must beat younger ID-stage early JAL
        pc_jump      = 1'b1;
        pc_jump_addr = ex_branch_target;
        ifid_flush   = 1'b1;
        idex_flush   = 1'b1;
    end
    else if (id_jal_early) begin
        // Priority 4: Early JAL redirect in ID stage
        // Safe only when no older redirect/flush is pending.
        pc_jump      = 1'b1;
        pc_jump_addr = id_jal_target;
        ifid_flush   = 1'b1;
        idex_flush   = 1'b0;
        exmem_flush  = 1'b0;
    end
    else if (load_use_stall) begin
    // Priority 3: classic load-use hazard
    // Hold PC and IF/ID, insert one bubble into EX.
    pc_stall   = 1'b1;
    ifid_stall = 1'b1;
    idex_flush = 1'b1;
    end
    else if (branch_wait_stall) begin
        // Priority 4: branch waits for source operands
        // Hold PC and IF/ID only.
        // IMPORTANT: do NOT flush ID/EX, otherwise the producer is destroyed.
        pc_stall   = 1'b1;
        ifid_stall = 1'b1;
    end
end

endmodule
