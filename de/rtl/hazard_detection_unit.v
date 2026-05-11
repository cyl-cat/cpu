`timescale 1ns / 1ps
// =============================================================================
// Module   : hazard_detection_unit
// Function : Detect hazards that require pipeline stalling.
//
//   1) load_use_stall:
//      Classic load-use hazard. Need:
//        - stall PC
//        - stall IF/ID
//        - flush ID/EX
//
//   2) branch_wait_stall:
//      Branch in ID depends on a result still in ID/EX or EX/MEM.
//      Need:
//        - stall PC
//        - stall IF/ID
//      BUT must NOT flush ID/EX, otherwise the producer instruction is lost.
// =============================================================================

module hazard_detection_unit (
    // From IF/ID register (instruction being decoded)
    input  wire [4:0]    id_rs1_addr,
    input  wire [4:0]    id_rs2_addr,
    input  wire          id_is_branch,

    // From ID/EX register
    input  wire          idex_mem_read,
    input  wire          idex_wr_reg_en,
    input  wire [4:0]    idex_rd_addr,

    // From EX/MEM register
    input  wire          exmem_mem_read,
    input  wire          exmem_wr_reg_en,
    input  wire [4:0]    exmem_rd_addr,

    // Outputs
    output wire          load_use_stall,
    output wire          branch_wait_stall
);

// ---------------------------------------------------------------------
// Classic load-use hazard:
// current IF/ID instruction needs the result of a load currently in ID/EX
// ---------------------------------------------------------------------
assign load_use_stall =
    idex_mem_read &&
    (idex_rd_addr != 5'h0) &&
    ((idex_rd_addr == id_rs1_addr) || (idex_rd_addr == id_rs2_addr));

// ---------------------------------------------------------------------
// Branch RAW waiting:
// branch in ID depends on values not yet stable.
//
// Case A: producer currently in ID/EX (ALU/load/etc.)
//         branch must wait, but producer must continue forward.
//
// Case B: producer currently in EX/MEM and is a LOAD.
//         data not yet written back, branch still needs to wait one more cycle.
//         For ALU results in EX/MEM, EX forwarding / regfile timing is enough;
//         do not over-stall those, to preserve performance.
// ---------------------------------------------------------------------
// 当前设计中 branch 真正比较发生在 EX 级，且已有 EX/MEM->EX、MEM/WB->EX 旁路。
// 因此除了“load 紧跟使用”之外，不需要再为 branch 单独停顿。
// 真正需要的那一种情况已经由 load_use_stall 覆盖。
assign branch_wait_stall = 1'b0;

endmodule