`timescale 1ns / 1ps
// =============================================================================
// Module   : riscv
// Function : Classic 5-stage pipelined RISC-V RV32I processor with:
//            - BHT (2-bit saturating counter, 256 entries)
//            - BTB (branch target buffer, 256 entries)
//            - Full data forwarding (EX/MEM→EX, MEM/WB→EX)
//            - Load-use hazard detection with 1-cycle stall
//            - Unified pipeline controller with misprediction detection
// =============================================================================
`include "riscv_defs.vh"

module riscv #(
    parameter string FILE = "rv32ui-p-addi.dat",
    parameter AW      = 32,
    parameter DW      = 32,
    parameter BHT_AW  = 7,
    parameter BTB_AW  = 6
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              rom_update_en,
    input  wire              rom_wr_en,
    input  wire [AW-1:0]     rom_wr_addr,
    input  wire [DW-1:0]     rom_wr_data,
    input  wire              external_int,
    output wire [DW-1:0]     test_case,
    output wire [DW-1:0]     reg_s10,
    output wire [DW-1:0]     reg_s11
);

wire new_rst_n = rst_n & (~rom_update_en);

// ====================================================================
//  Wire declarations
// ====================================================================
// Pipeline controller
wire            pc_stall, pc_jump;
wire [AW-1:0]  pc_jump_addr;
wire            ifid_stall, ifid_flush, idex_flush, exmem_flush;

// BHT/BTB prediction (IF stage)
wire            bht_predict_taken;
wire            btb_hit;
wire [AW-1:0]   btb_target;
wire            if_predict_taken;
wire [AW-1:0]   if_predict_target;

assign if_predict_taken  = bht_predict_taken & btb_hit;
assign if_predict_target = btb_target;

// BHT/BTB update (from pipeline controller, EX stage)
wire            bht_update_en, bht_actual_taken;
wire [AW-1:0]  bht_update_pc;
wire            btb_update_en, btb_update_taken;
wire [AW-1:0]  btb_update_pc, btb_update_target;

// IF stage
wire [AW-1:0]  if_pc;
wire [DW-1:0]  if_instr;

// IF/ID
wire [AW-1:0]  ifid_pc;
wire [DW-1:0]  ifid_instr;
wire            ifid_predict_taken;
wire [AW-1:0]  ifid_predict_target;

// ID stage
wire [4:0]     id_rs1_addr, id_rs2_addr, id_rd_addr;
wire [DW-1:0]  id_imm, id_rs1_data, id_rs2_data;
wire           id_wr_reg_en, id_mem_read, id_mem_write;
wire           id_branch, id_jump, id_jump_r;
wire           id_wr_csr_en, id_is_lui, id_is_auipc, id_is_fence, id_is_csr;
wire [AW-1:0]  id_rd_csr_addr;
wire            id_jal_early;
wire [AW-1:0]   id_jal_early_target;
wire            id_predict_taken_eff;
wire [AW-1:0]   id_predict_target_eff;

// 仅对真实 JAL 做 ID 级提前跳转。
// 注意：不能把 FENCE 一起并进来；当前设计里 FENCE 也会置 jump=1，
// 但其正确目标是 pc+4，而不是 pc+imm。
assign id_jal_early        = id_jump & ~id_jump_r & ~id_is_fence;
assign id_jal_early_target = ifid_pc + id_imm;

// 对于 JAL，直接用 ID 级的精确目标覆盖 IF 级预测，避免到 EX 级再 flush
assign id_predict_taken_eff  = id_jal_early ? 1'b1 : ifid_predict_taken;
assign id_predict_target_eff = id_jal_early ? id_jal_early_target : ifid_predict_target;

// ID/EX
wire [AW-1:0]  idex_pc;
wire [DW-1:0]  idex_instr, idex_rs1_data, idex_rs2_data, idex_imm;
wire [4:0]     idex_rs1_addr, idex_rs2_addr, idex_rd_addr;
wire           idex_wr_reg_en, idex_mem_read, idex_mem_write;
wire           idex_branch, idex_jump, idex_jump_r;
wire           idex_wr_csr_en, idex_is_lui, idex_is_auipc, idex_is_fence, idex_is_csr;
wire [AW-1:0]  idex_rd_csr_addr;
wire           idex_predict_taken;
wire [AW-1:0]  idex_predict_target;

// Forwarding
wire [1:0]     forward_a, forward_b;
reg  [DW-1:0]  fwd_rs1_data, fwd_rs2_data;

// EX stage
wire [DW-1:0]  ex_alu_result, ex_wr_reg_data, ex_mem_wr_data, ex_csr_wr_data;
wire           ex_branch_taken;
wire [AW-1:0]  ex_branch_target;
wire [DW-1:0]  ex_rd_csr_data, ex_rd_csr_data_eff;

// EX/MEM
wire [AW-1:0]  exmem_pc;
wire [DW-1:0]  exmem_instr, exmem_alu_result, exmem_wr_reg_data, exmem_mem_wr_data;
wire [4:0]     exmem_rd_addr;
wire           exmem_wr_reg_en, exmem_mem_read, exmem_mem_write, exmem_wr_csr_en;
wire [AW-1:0]  exmem_csr_wr_addr;
wire [DW-1:0]  exmem_csr_wr_data;

// MEM stage
wire [3:0] ram_wr_be;
wire [DW-1:0]  mem_wr_reg_data, mem_rd_data;
wire [AW-1:0]  ram_rd_addr, ram_wr_addr;
wire [DW-1:0]  ram_rd_data, ram_wr_data;
wire           ram_wr_en;

// MEM/WB
wire [DW-1:0]  memwb_wr_reg_data;
wire [4:0]     memwb_rd_addr;
wire           memwb_wr_reg_en;

// Hazard
wire load_use_stall;
wire branch_wait_stall;

// Interrupt
wire           int_en;
wire [AW-1:0]  int_addr;
wire           set_csr_reg;

wire [DW-1:0]  mstatus_in, mie_in, mtvec_in, mepc_in;
wire [DW-1:0]  mstatus_out, mcause_out, mepc_out, mip_out, mtval_out;
wire [DW-1:0]  ustatus_in, uie_in, utvec_in, uepc_in;
wire [DW-1:0]  ustatus_out, ucause_out, uepc_out, uip_out, utval_out;

wire           timer_int;
wire           software_int = 1'b0;          // no internal SW interrupt source in this top
wire           external_int_clear, software_int_clear, timer_int_clear;

wire clint_jump_en = (ex_branch_taken & idex_branch) |
                     (idex_jump & !idex_branch);

// ====================================================================
//  BHT — Branch History Table
// ====================================================================
bht #(.BHT_AW(BHT_AW)) u_bht (
    .clk            (clk),
    .rst_n          (new_rst_n),
    .if_pc          (if_pc),
    .predict_taken  (bht_predict_taken),
    .update_en      (bht_update_en),
    .update_pc      (bht_update_pc),
    .actual_taken   (bht_actual_taken)
);

// // ====================================================================
// //  BTB — Branch Target Buffer
// // ====================================================================
btb #(.AW(AW), .BTB_AW(BTB_AW)) u_btb (
    .clk            (clk),
    .rst_n          (new_rst_n),
    .if_pc          (if_pc),
    .btb_hit        (btb_hit),
    .btb_target     (btb_target),
    .update_en      (btb_update_en),
    .update_pc      (btb_update_pc),
    .update_target  (btb_update_target),
    .update_taken   (btb_update_taken)
);

// ====================================================================
//  Pipeline Controller (with misprediction detection)
// ====================================================================
pipeline_controller #(.AW(AW)) u_ctrl (
    .ex_branch         (idex_branch),
    .ex_branch_taken   (ex_branch_taken),
    .ex_branch_target  (ex_branch_target),
    .ex_jump           (idex_jump & !idex_branch),
    .ex_jump_r         (idex_jump_r),
    .ex_pc             (idex_pc),
    .ex_predict_taken  (idex_predict_taken),
    .ex_predict_target (idex_predict_target),

    .id_jal_early      (id_jal_early),
    .id_jal_target     (id_jal_early_target),

    .int_en            (int_en),
    .int_addr          (int_addr),
    .load_use_stall    (load_use_stall),
    .branch_wait_stall (branch_wait_stall),
    .pc_stall          (pc_stall),
    .pc_jump           (pc_jump),
    .pc_jump_addr      (pc_jump_addr),
    .ifid_stall        (ifid_stall),
    .ifid_flush        (ifid_flush),
    .idex_flush        (idex_flush),
    .exmem_flush       (exmem_flush),
    .bht_update_en     (bht_update_en),
    .bht_update_pc     (bht_update_pc),
    .bht_actual_taken  (bht_actual_taken),
    .btb_update_en     (btb_update_en),
    .btb_update_pc     (btb_update_pc),
    .btb_update_target (btb_update_target),
    .btb_update_taken  (btb_update_taken)
);

// ====================================================================
//  Hazard Detection Unit
// ====================================================================
hazard_detection_unit u_hdu (
    .id_rs1_addr        (id_rs1_addr),
    .id_rs2_addr        (id_rs2_addr),
    .id_is_branch       (id_branch),

    .idex_mem_read      (idex_mem_read),
    .idex_wr_reg_en     (idex_wr_reg_en),
    .idex_rd_addr       (idex_rd_addr),

    .exmem_mem_read     (exmem_mem_read),
    .exmem_wr_reg_en    (exmem_wr_reg_en),
    .exmem_rd_addr      (exmem_rd_addr),

    .load_use_stall     (load_use_stall),
    .branch_wait_stall  (branch_wait_stall)
);

// ====================================================================
//  Forwarding Unit + MUXes
// ====================================================================
forwarding_unit u_fwd (
    .ex_rs1_addr    (idex_rs1_addr),
    .ex_rs2_addr    (idex_rs2_addr),
    .mem_wr_reg_en  (exmem_wr_reg_en),
    .mem_rd_addr    (exmem_rd_addr),
    .wb_wr_reg_en   (memwb_wr_reg_en),
    .wb_rd_addr     (memwb_rd_addr),
    .forward_a      (forward_a),
    .forward_b      (forward_b)
);

always @(*) begin
    case (forward_a)
        2'b10:   fwd_rs1_data = exmem_wr_reg_data;
        2'b01:   fwd_rs1_data = memwb_wr_reg_data;
        default: fwd_rs1_data = idex_rs1_data;
    endcase
end
always @(*) begin
    case (forward_b)
        2'b10:   fwd_rs2_data = exmem_wr_reg_data;
        2'b01:   fwd_rs2_data = memwb_wr_reg_data;
        default: fwd_rs2_data = idex_rs2_data;
    endcase
end

// ====================================================================
//  Stage 1: IF
// ====================================================================
pc_counter #(.AW(AW)) u_pc (
    .clk           (clk),
    .rst_n         (rst_n),
    .rom_update_en (rom_update_en),
    .pc_stall      (pc_stall),
    .pc_jump       (pc_jump),
    .pc_jump_addr  (pc_jump_addr),
    .predict_taken (if_predict_taken),
    .predict_target(if_predict_target),
    .pc_out        (if_pc)
);

rom #(.FILE(FILE), .AW(AW), .DW(DW)) u_rom (
    .clk           (clk),
    .rst_n         (rst_n),
    .update_en     (rom_update_en),
    .instr_wr_en   (rom_wr_en),
    .instr_wr_addr (rom_wr_addr),
    .instr_wr_data (rom_wr_data),
    .instr_addr    (if_pc),
    .instr_out     (if_instr)
);


// ====================================================================
//  IF/ID
// ====================================================================
if2id #(.AW(AW), .DW(DW)) u_if2id (
    .clk                (clk),
    .rst_n              (new_rst_n),
    .flush              (ifid_flush),
    .stall              (ifid_stall),
    .pc_in              (if_pc),
    .instr_in           (if_instr),
    .predict_taken_in   (if_predict_taken),
    .predict_target_in  (if_predict_target),
    .pc_out             (ifid_pc),
    .instr_out          (ifid_instr),
    .predict_taken_out  (ifid_predict_taken),
    .predict_target_out (ifid_predict_target)
);

// ====================================================================
//  Stage 2: ID
// ====================================================================
id_stage #(.AW(AW), .DW(DW)) u_id (
    .rst_n       (new_rst_n),
    .pc_in       (ifid_pc),
    .instr_in    (ifid_instr),
    .rs1_addr    (id_rs1_addr),
    .rs2_addr    (id_rs2_addr),
    .rd_addr     (id_rd_addr),
    .imm         (id_imm),
    .wr_reg_en   (id_wr_reg_en),
    .mem_read    (id_mem_read),
    .mem_write   (id_mem_write),
    .branch      (id_branch),
    .jump        (id_jump),
    .jump_r      (id_jump_r),
    .wr_csr_en   (id_wr_csr_en),
    .rd_csr_addr (id_rd_csr_addr),
    .is_lui      (id_is_lui),
    .is_auipc    (id_is_auipc),
    .is_fence    (id_is_fence),
    .is_csr      (id_is_csr)
);

register_file #(.DW(DW)) u_regfile (
    .clk         (clk),
    .rst_n       (new_rst_n),
    .rd_rs1_addr (id_rs1_addr),
    .rd_rs2_addr (id_rs2_addr),
    .rd_rs1_data (id_rs1_data),
    .rd_rs2_data (id_rs2_data),
    .wr_en       (memwb_wr_reg_en),
    .wr_addr     (memwb_rd_addr),
    .wr_data     (memwb_wr_reg_data),
    .test_case   (test_case),
    .reg_s10     (reg_s10),
    .reg_s11     (reg_s11)
);

// ====================================================================
//  ID/EX
// ====================================================================
id2ex #(.AW(AW), .DW(DW)) u_id2ex (
    .clk               (clk),
    .rst_n             (new_rst_n),
    .flush             (idex_flush),
    .pc_in             (ifid_pc),
    .instr_in          (ifid_instr),
    .rs1_data_in       (id_rs1_data),
    .rs2_data_in       (id_rs2_data),
    .imm_in            (id_imm),
    .rs1_addr_in       (id_rs1_addr),
    .rs2_addr_in       (id_rs2_addr),
    .rd_addr_in        (id_rd_addr),
    .wr_reg_en_in      (id_wr_reg_en),
    .mem_read_in       (id_mem_read),
    .mem_write_in      (id_mem_write),
    .branch_in         (id_branch),
    .jump_in           (id_jump),
    .jump_r_in         (id_jump_r),
    .wr_csr_en_in      (id_wr_csr_en),
    .rd_csr_addr_in    (id_rd_csr_addr),
    .is_lui_in         (id_is_lui),
    .is_auipc_in       (id_is_auipc),
    .is_fence_in       (id_is_fence),
    .is_csr_in         (id_is_csr),
    .predict_taken_in  (id_predict_taken_eff),
    .predict_target_in (id_predict_target_eff),
    .pc_out            (idex_pc),
    .instr_out         (idex_instr),
    .rs1_data_out      (idex_rs1_data),
    .rs2_data_out      (idex_rs2_data),
    .imm_out           (idex_imm),
    .rs1_addr_out      (idex_rs1_addr),
    .rs2_addr_out      (idex_rs2_addr),
    .rd_addr_out       (idex_rd_addr),
    .wr_reg_en_out     (idex_wr_reg_en),
    .mem_read_out      (idex_mem_read),
    .mem_write_out     (idex_mem_write),
    .branch_out        (idex_branch),
    .jump_out          (idex_jump),
    .jump_r_out        (idex_jump_r),
    .wr_csr_en_out     (idex_wr_csr_en),
    .rd_csr_addr_out   (idex_rd_csr_addr),
    .is_lui_out        (idex_is_lui),
    .is_auipc_out      (idex_is_auipc),
    .is_fence_out      (idex_is_fence),
    .is_csr_out        (idex_is_csr),
    .predict_taken_out (idex_predict_taken),
    .predict_target_out(idex_predict_target)
);

// ====================================================================
//  Stage 3: EX
// ====================================================================
ex_stage #(.AW(AW), .DW(DW)) u_ex (
    .pc           (idex_pc),
    .instr        (idex_instr),
    .rs1_data     (fwd_rs1_data),
    .rs2_data     (fwd_rs2_data),
    .imm          (idex_imm),
    .branch       (idex_branch),
    .jump         (idex_jump),
    .jump_r       (idex_jump_r),
    .is_lui       (idex_is_lui),
    .is_auipc     (idex_is_auipc),
    .is_fence     (idex_is_fence),
    .is_csr       (idex_is_csr),
    .mem_read     (idex_mem_read),
    .mem_write    (idex_mem_write),
    .int_en       (int_en),
    .rd_csr_data  (ex_rd_csr_data_eff),
    .alu_result   (ex_alu_result),
    .wr_reg_data  (ex_wr_reg_data),
    .branch_taken (ex_branch_taken),
    .branch_target(ex_branch_target),
    .csr_wr_data  (ex_csr_wr_data),
    .mem_wr_data  (ex_mem_wr_data)
);

// ====================================================================
//  EX/MEM
// ====================================================================
ex2mem #(.AW(AW), .DW(DW)) u_ex2mem (
    .clk             (clk),
    .rst_n           (new_rst_n),
    .flush           (exmem_flush),
    .pc_in           (idex_pc),
    .instr_in        (idex_instr),
    .alu_result_in   (ex_alu_result),
    .wr_reg_data_in  (ex_wr_reg_data),
    .mem_wr_data_in  (ex_mem_wr_data),
    .rd_addr_in      (idex_rd_addr),
    .wr_reg_en_in    (idex_wr_reg_en),
    .mem_read_in     (idex_mem_read),
    .mem_write_in    (idex_mem_write),
    .wr_csr_en_in    (idex_wr_csr_en),
    .csr_wr_addr_in  ({20'h0, idex_instr[31:20]}),
    .csr_wr_data_in  (ex_csr_wr_data),
    .pc_out          (exmem_pc),
    .instr_out       (exmem_instr),
    .alu_result_out  (exmem_alu_result),
    .wr_reg_data_out (exmem_wr_reg_data),
    .mem_wr_data_out (exmem_mem_wr_data),
    .rd_addr_out     (exmem_rd_addr),
    .wr_reg_en_out   (exmem_wr_reg_en),
    .mem_read_out    (exmem_mem_read),
    .mem_write_out   (exmem_mem_write),
    .wr_csr_en_out   (exmem_wr_csr_en),
    .csr_wr_addr_out (exmem_csr_wr_addr),
    .csr_wr_data_out (exmem_csr_wr_data)
);

// ====================================================================
//  Stage 4: MEM
// ====================================================================
mem_stage #(.AW(AW), .DW(DW)) u_mem (
    .instr          (exmem_instr),
    .alu_result     (exmem_alu_result),
    .wr_reg_data_in (exmem_wr_reg_data),
    .mem_wr_data_in (exmem_mem_wr_data),
    .mem_read       (exmem_mem_read),
    .mem_write      (exmem_mem_write),
    .ram_rd_addr    (ram_rd_addr),
    .ram_rd_data    (ram_rd_data),
    .ram_wr_en      (ram_wr_en),
    .ram_wr_addr    (ram_wr_addr),
    .ram_wr_data    (ram_wr_data),
    .mem_rd_data    (mem_rd_data),
    .wr_reg_data_out(mem_wr_reg_data),
    .ram_wr_be     (ram_wr_be)
);

ram #(
    .FILE(FILE),
    .AW  (AW),
    .DW  (DW)
) u_ram (
    .clk    (clk),
    .rst_n  (new_rst_n),
    .wr_en  (ram_wr_en),
    .wr_addr(ram_wr_addr),
    .wr_data(ram_wr_data),
    .rd_addr(ram_rd_addr),
    .rd_data(ram_rd_data),
    .wr_be  (ram_wr_be)
);

// ====================================================================
//  MEM/WB + Stage 5: WB
// ====================================================================
mem2wb #(.AW(AW), .DW(DW)) u_mem2wb (
    .clk             (clk),
    .rst_n           (new_rst_n),
    .wr_reg_data_in  (mem_wr_reg_data),
    .rd_addr_in      (exmem_rd_addr),
    .wr_reg_en_in    (exmem_wr_reg_en),
    .wr_reg_data_out (memwb_wr_reg_data),
    .rd_addr_out     (memwb_rd_addr),
    .wr_reg_en_out   (memwb_wr_reg_en)
);

// ====================================================================
//  CSR + Interrupt
// ====================================================================

wire csr_fwd_hit;
assign csr_fwd_hit =
    exmem_wr_csr_en &&
    (exmem_csr_wr_addr[11:0] == idex_rd_csr_addr[11:0]);

assign ex_rd_csr_data_eff =
    csr_fwd_hit ? exmem_csr_wr_data : ex_rd_csr_data;

csr_top_reg #(.AW(AW), .DW(DW)) u_csr (
    .clk               (clk),
    .rst_n             (new_rst_n),
    .rd_addr           (idex_rd_csr_addr),
    .rd_data           (ex_rd_csr_data),
    .wr_en             (exmem_wr_csr_en),
    .wr_addr           (exmem_csr_wr_addr),
    .wr_data           (exmem_csr_wr_data),
    .mstatus_out       (mstatus_in),   .mie_out    (mie_in),
    .mtvec_out         (mtvec_in),     .mepc_out   (mepc_in),
    .mstatus_in        (mstatus_out),  .mcause_in  (mcause_out),
    .mepc_in           (mepc_out),     .mip_in     (mip_out),
    .mtval_in          (mtval_out),
    .ustatus_out       (ustatus_in),   .uie_out    (uie_in),
    .utvec_out         (utvec_in),     .uepc_out   (uepc_in),
    .ustatus_in        (ustatus_out),  .ucause_in  (ucause_out),
    .uepc_in           (uepc_out),     .uip_in     (uip_out),
    .utval_in          (utval_out),
    .set_csr_reg       (set_csr_reg),
    .timer_int         (timer_int),
    .external_int_clear(external_int_clear),
    .software_int_clear(software_int_clear),
    .timer_int_clear   (timer_int_clear)
);

clint #(.AW(AW), .DW(DW)) u_clint (
    .clk               (clk),
    .rst_n             (new_rst_n),
    .jump_en_in        (clint_jump_en),
    .instr_addr_in     (idex_pc),
    .instr_in          (idex_instr),
    .external_int_in   (external_int),
    .software_int_in   (software_int),
    .timer_int_in      (timer_int),
    .external_int_clear(external_int_clear),
    .software_int_clear(software_int_clear),
    .timer_int_clear   (timer_int_clear),
    .mstatus_in  (mstatus_in),  .mie_in    (mie_in),
    .mtvec_in    (mtvec_in),    .mepc_in   (mepc_in),
    .mstatus_out (mstatus_out), .mcause_out(mcause_out),
    .mepc_out    (mepc_out),    .mip_out   (mip_out),
    .mtval_out   (mtval_out),
    .ustatus_in  (ustatus_in),  .uie_in    (uie_in),
    .utvec_in    (utvec_in),    .uepc_in   (uepc_in),
    .ustatus_out (ustatus_out), .ucause_out(ucause_out),
    .uepc_out    (uepc_out),    .uip_out   (uip_out),
    .utval_out   (utval_out),
    .set_csr_reg (set_csr_reg),
    .int_en      (int_en),
    .int_addr    (int_addr)
);

endmodule
