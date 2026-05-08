`timescale 1ns / 1ps
// =============================================================================
// Module   : ex_stage
// Function : Execution stage for 5-stage pipeline (combinational).
//            - ALU operations (R/I/shift/compare)
//            - Branch condition evaluation
//            - Jump target computation
//            - Address computation for load/store
//            - CSR operation computation
//            Does NOT access memory (that's MEM stage).
//            Receives forwarded operands via rs1_data/rs2_data inputs.
//
// Fix log:
//   [FIX-1] SLTI now compares rs1 vs imm (signed), not rs1 vs rs2.
//   [FIX-2] Added int_en input to suppress all outputs during interrupt.
//   [FIX-3] Comparison wires split into reg-reg (B/R-type) and reg-imm (I-type).
// =============================================================================
`include "riscv_defs.vh"

module ex_stage #(
    parameter AW = 32,
    parameter DW = 32
)(
    // From ID/EX register
    input  wire [AW-1:0]     pc,
    input  wire [DW-1:0]     instr,
    input  wire [DW-1:0]     rs1_data,       // after forwarding MUX
    input  wire [DW-1:0]     rs2_data,       // after forwarding MUX
    input  wire [DW-1:0]     imm,
    input  wire              branch,
    input  wire              jump,
    input  wire              jump_r,
    input  wire              is_lui,
    input  wire              is_auipc,
    input  wire              is_fence,
    input  wire              is_csr,
    input  wire              mem_read,
    input  wire              mem_write,
    // [FIX-2] Interrupt suppression
    input  wire              int_en,
    // CSR read data
    input  wire [DW-1:0]     rd_csr_data,
    // Outputs
    output reg  [DW-1:0]     alu_result,     // ALU / address result
    output reg  [DW-1:0]     wr_reg_data,    // data to write to rd (non-load)
    output reg               branch_taken,   // branch actually taken
    output reg  [AW-1:0]     branch_target,  // branch/jump target address
    output reg  [DW-1:0]     csr_wr_data,    // data to write to CSR
    output wire [DW-1:0]     mem_wr_data     // rs2 data for store (passed through)
);

wire [6:0] opcode = instr[6:0];
wire [2:0] func3  = instr[14:12];
wire [6:0] func7  = instr[31:25];

// [FIX-3] Register-register comparisons (for B-type and R-type)
wire        rr_equal         = (rs1_data == rs2_data);
wire        rr_less_signed   = ($signed(rs1_data) < $signed(rs2_data));
wire        rr_less_unsigned = (rs1_data < rs2_data);

// [FIX-1] Register-immediate comparisons (for I-type SLTI/SLTIU)
wire        ri_less_signed   = ($signed(rs1_data) < $signed(imm));
wire        ri_less_unsigned = (rs1_data < imm);

// Shift helpers
wire [DW-1:0] sr_shift      = rs1_data >> rs2_data[4:0];
wire [DW-1:0] sr_shift_mask = {DW{1'b1}} >> rs2_data[4:0];
wire [DW-1:0] sri_shift     = rs1_data >> imm[4:0];
wire [DW-1:0] sri_mask      = {DW{1'b1}} >> imm[4:0];

// Branch immediate (B-type encoding)
wire [31:0] b_imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};

// Store data pass-through
assign mem_wr_data = rs2_data;

// ALU / result computation
always @(*) begin
    alu_result    = {DW{1'b0}};
    wr_reg_data   = {DW{1'b0}};
    branch_taken  = 1'b0;
    branch_target = {AW{1'b0}};
    csr_wr_data   = {DW{1'b0}};

    // [FIX-2] Suppress all outputs during interrupt handling
    if (int_en) begin
        // All outputs stay at zero defaults
    end

    // ---- Address for load/store: rs1 + imm ----
    else if (mem_read || mem_write)
        alu_result = rs1_data + imm;

    // ---- LUI ----
    else if (is_lui) begin
        alu_result  = imm;
        wr_reg_data = imm;
    end

    // ---- AUIPC ----
    else if (is_auipc) begin
        alu_result  = pc + imm;
        wr_reg_data = pc + imm;
    end

    // ---- FENCE ----
    else if (is_fence) begin
        branch_taken  = 1'b1;
        branch_target = pc + 32'h4;
    end

    // ---- CSR ----
    else if (is_csr) begin
        wr_reg_data = rd_csr_data;
        case (func3)
            `INST_CSRRW:  csr_wr_data = rs1_data;
            `INST_CSRRS:  csr_wr_data = rd_csr_data | rs1_data;
            `INST_CSRRC:  csr_wr_data = rd_csr_data & (~rs1_data);
            `INST_CSRRWI: csr_wr_data = {27'h0, instr[19:15]};
            `INST_CSRRSI: csr_wr_data = rd_csr_data | {27'h0, instr[19:15]};
            `INST_CSRRCI: csr_wr_data = rd_csr_data & (~{27'h0, instr[19:15]});
            default:      csr_wr_data = {DW{1'b0}};
        endcase
    end

    // ---- Branch ----
    else if (branch) begin
        case (func3)
            `INST_BEQ:  branch_taken = rr_equal;
            `INST_BNE:  branch_taken = ~rr_equal;
            `INST_BLT:  branch_taken = rr_less_signed;
            `INST_BGE:  branch_taken = ~rr_less_signed;
            `INST_BLTU: branch_taken = rr_less_unsigned;
            `INST_BGEU: branch_taken = ~rr_less_unsigned;
            default:    branch_taken = 1'b0;
        endcase
        branch_target = pc + b_imm;
    end

    // ---- JAL ----
    else if (jump && !jump_r) begin
        wr_reg_data   = pc + 32'h4;
        branch_taken  = 1'b1;
        branch_target = pc + imm;
    end

    // ---- JALR ----
    else if (jump && jump_r) begin
        wr_reg_data   = pc + 32'h4;
        branch_taken  = 1'b1;
        branch_target = (rs1_data + imm) & 32'hFFFFFFFE; // clear LSB per spec
    end

    // ---- I-type ALU ----
    else if (opcode == `INST_TYPE_I) begin
        case (func3)
            `INST_ADDI: begin
                alu_result  = rs1_data + imm;
                wr_reg_data = rs1_data + imm;
            end
            `INST_SLTI: begin  // [FIX-1] use ri_less_signed (rs1 vs imm)
                alu_result  = {31'b0, ri_less_signed};
                wr_reg_data = {31'b0, ri_less_signed};
            end
            `INST_SLTIU: begin // already correct (rs1 vs imm)
                alu_result  = {31'b0, ri_less_unsigned};
                wr_reg_data = {31'b0, ri_less_unsigned};
            end
            `INST_XORI: begin
                alu_result  = rs1_data ^ imm;
                wr_reg_data = rs1_data ^ imm;
            end
            `INST_ORI: begin
                alu_result  = rs1_data | imm;
                wr_reg_data = rs1_data | imm;
            end
            `INST_ANDI: begin
                alu_result  = rs1_data & imm;
                wr_reg_data = rs1_data & imm;
            end
            `INST_SLLI: begin
                alu_result  = rs1_data << imm[4:0];
                wr_reg_data = rs1_data << imm[4:0];
            end
            `INST_SRI: begin
                if (instr[30]) begin // SRAI
                    alu_result  = $signed(rs1_data) >>> imm[4:0];
                    wr_reg_data = alu_result;
                end else begin       // SRLI
                    alu_result  = rs1_data >> imm[4:0];
                    wr_reg_data = alu_result;
                end
            end
            default: ;
        endcase
    end

    // ---- R-type ALU ----
    else if (opcode == `INST_TYPE_R_M) begin
        if ((func7 == 7'b0000000) || (func7 == 7'b0100000)) begin
            case (func3)
                `INST_ADD_SUB: begin
                    alu_result  = func7[5] ? (rs1_data - rs2_data) : (rs1_data + rs2_data);
                    wr_reg_data = alu_result;
                end
                `INST_SLL: begin
                    alu_result  = rs1_data << rs2_data[4:0];
                    wr_reg_data = alu_result;
                end
                `INST_SLT: begin   // R-type: compare rs1 vs rs2 (correct)
                    alu_result  = {31'b0, rr_less_signed};
                    wr_reg_data = alu_result;
                end
                `INST_SLTU: begin  // R-type: compare rs1 vs rs2 (correct)
                    alu_result  = {31'b0, rr_less_unsigned};
                    wr_reg_data = alu_result;
                end
                `INST_XOR: begin
                    alu_result  = rs1_data ^ rs2_data;
                    wr_reg_data = alu_result;
                end
                `INST_SR: begin
                    if (instr[30]) begin // SRA
                        alu_result  = $signed(rs1_data) >>> rs2_data[4:0];
                        wr_reg_data = alu_result;
                    end else begin       // SRL
                        alu_result  = rs1_data >> rs2_data[4:0];
                        wr_reg_data = alu_result;
                    end
                end
                `INST_OR: begin
                    alu_result  = rs1_data | rs2_data;
                    wr_reg_data = alu_result;
                end
                `INST_AND: begin
                    alu_result  = rs1_data & rs2_data;
                    wr_reg_data = alu_result;
                end
                default: ;
            endcase
        end
        // M-extension (mul/div) — not yet implemented, results are 0
        else if (func7 == 7'b0000001) begin
            alu_result  = {DW{1'b0}};
            wr_reg_data = {DW{1'b0}};
        end
    end
end

endmodule
