`timescale 1ns / 1ps
// =============================================================================
// Module   : id_stage
// Function : Instruction decode for 5-stage pipeline (combinational).
//
// Fix log:
//   [FIX-3] Added ECALL/EBREAK/MRET/URET detection — these share CSR opcode
//           but must NOT produce register/CSR write enables.
//   [FIX-4] Added NOP_OP handling (custom bubble opcode from original design).
// =============================================================================
`include "riscv_defs.vh"

module id_stage #(
    parameter AW = 32,
    parameter DW = 32
)(
    input  wire              rst_n,
    input  wire [AW-1:0]     pc_in,
    input  wire [DW-1:0]     instr_in,
    // Register file interface
    output wire [4:0]        rs1_addr,
    output wire [4:0]        rs2_addr,
    // Decoded outputs
    output wire [4:0]        rd_addr,
    output reg  [DW-1:0]     imm,
    // Control signals
    output reg               wr_reg_en,
    output reg               mem_read,
    output reg               mem_write,
    output reg               branch,
    output reg               jump,
    output reg               jump_r,
    output reg               wr_csr_en,
    output reg  [AW-1:0]     rd_csr_addr,
    output reg               is_lui,
    output reg               is_auipc,
    output reg               is_fence,
    output reg               is_csr
);

wire [6:0] opcode = instr_in[6:0];
wire [2:0] func3  = instr_in[14:12];

assign rs1_addr = instr_in[19:15];
assign rs2_addr = instr_in[24:20];
assign rd_addr  = instr_in[11:7];

// [FIX-3] Special instruction detection
wire is_ecall  = (instr_in == `INST_ECALL);
wire is_ebreak = (instr_in == `INST_EBREAK);
wire is_mret   = (instr_in == `INST_MRET);
wire is_uret   = (instr_in == `INST_URET);
wire is_special = is_ecall | is_ebreak | is_mret | is_uret;

// Immediate generation
always @(*) begin
    case (opcode)
        `INST_TYPE_I, `INST_TYPE_L, `INST_JALR:
            imm = {{20{instr_in[31]}}, instr_in[31:20]};
        `INST_TYPE_S:
            imm = {{20{instr_in[31]}}, instr_in[31:25], instr_in[11:7]};
        `INST_TYPE_B:
            imm = {{20{instr_in[31]}}, instr_in[7], instr_in[30:25], instr_in[11:8], 1'b0};
        `INST_JAL:
            imm = {{12{instr_in[31]}}, instr_in[19:12], instr_in[20], instr_in[30:21], 1'b0};
        `INST_LUI, `INST_LUIPC:
            imm = {instr_in[31:12], 12'h0};
        `INST_CSR:
            imm = {20'h0, instr_in[31:20]};
        default:
            imm = 32'h0;
    endcase
end

// Control signal generation
always @(*) begin
    if (!rst_n) begin
        wr_reg_en  = 1'b0;  mem_read   = 1'b0;  mem_write  = 1'b0;
        branch     = 1'b0;  jump       = 1'b0;  jump_r     = 1'b0;
        wr_csr_en  = 1'b0;  rd_csr_addr= {AW{1'b0}};
        is_lui     = 1'b0;  is_auipc   = 1'b0;  is_fence   = 1'b0;
        is_csr     = 1'b0;
    end
    else begin
        // Defaults — all disabled
        wr_reg_en  = 1'b0;  mem_read   = 1'b0;  mem_write  = 1'b0;
        branch     = 1'b0;  jump       = 1'b0;  jump_r     = 1'b0;
        wr_csr_en  = 1'b0;  rd_csr_addr= {AW{1'b0}};
        is_lui     = 1'b0;  is_auipc   = 1'b0;  is_fence   = 1'b0;
        is_csr     = 1'b0;

        // [FIX-3] ECALL/EBREAK/MRET/URET: no register/CSR writes.
        // clint module detects these by matching full 32-bit instruction word.
        if (is_special) begin
            // All control signals stay at defaults (disabled)
        end
        else begin
            case (opcode)
                `INST_TYPE_I: wr_reg_en = 1'b1;
                `INST_TYPE_R_M: wr_reg_en = 1'b1;
                `INST_TYPE_L: begin wr_reg_en = 1'b1; mem_read = 1'b1; end
                `INST_TYPE_S: mem_write = 1'b1;
                `INST_TYPE_B: branch = 1'b1;
                `INST_JAL:    begin wr_reg_en = 1'b1; jump = 1'b1; end
                `INST_JALR:   begin wr_reg_en = 1'b1; jump = 1'b1; jump_r = 1'b1; end
                `INST_LUI:    begin wr_reg_en = 1'b1; is_lui = 1'b1; end
                `INST_LUIPC:  begin wr_reg_en = 1'b1; is_auipc = 1'b1; end
                `INST_CSR: begin
                    wr_reg_en  = 1'b1;
                    wr_csr_en  = 1'b1;
                    rd_csr_addr= imm;
                    is_csr     = 1'b1;
                end
                `INST_FENCE:  begin jump = 1'b1; is_fence = 1'b1; end
                `INST_NOP_OP: ;  // [FIX-4] custom NOP — all disabled
                default: ;
            endcase
        end
    end
end

endmodule
