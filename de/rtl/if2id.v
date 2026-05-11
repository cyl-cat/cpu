`timescale 1ns / 1ps
// =============================================================================
// Module   : if2id
// Function : IF/ID 流水寄存器。
//            该模块位于取指阶段 IF 和译码阶段 ID 之间，用于锁存取指
//            得到的 PC 和指令。同时，它也会锁存 IF 阶段产生的分支预测
//            信息，方便后续 EX 阶段判断预测是否正确。
// =============================================================================
`include "riscv_defs.vh"

module if2id #(
    parameter AW = 32,
    parameter DW = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    // flush 的优先级高于 stall。当当前取到的指令需要被清除时，
    // 例如分支预测失败、跳转重定向或中断重定向，就向 ID 阶段插入气泡。
    input  wire              flush,
    // stall 用于保持当前 IF/ID 寄存器内容不变。当后级暂时不能接收
    // 新指令时使用，例如 load-use 冒险导致流水线暂停。
    input  wire              stall,
    // 来自 IF 阶段的取指 PC 和指令。
    input  wire [AW-1:0]     pc_in,
    input  wire [DW-1:0]     instr_in,
    // 来自 IF 阶段的分支预测结果。预测信息必须和对应指令一起向后传递，
    // 否则 EX 阶段会拿实际分支结果和错误的预测信息进行比较。
    input  wire              predict_taken_in,
    input  wire [AW-1:0]     predict_target_in,
    // 输出到 ID 阶段的寄存器值。
    output reg  [AW-1:0]     pc_out,
    output reg  [DW-1:0]     instr_out,
    output reg               predict_taken_out,
    output reg  [AW-1:0]     predict_target_out
);

always @(posedge clk) begin
    // 复位时向 ID 阶段插入一个干净的气泡。这里写入 NOP，而不是全 0，
    // 是为了让后级译码逻辑看到一条合法的空操作指令。
    if (!rst_n) begin
        pc_out             <= {AW{1'b0}};
        instr_out          <= `INST_NOP;
        predict_taken_out  <= 1'b0;
        predict_target_out <= {AW{1'b0}};
    end
    // flush 时同样插入气泡。被清除的指令不能继续影响后级逻辑，
    // 因此对应的分支预测信息也要一起清零。
    else if (flush) begin
        pc_out             <= {AW{1'b0}};
        instr_out          <= `INST_NOP;
        predict_taken_out  <= 1'b0;
        predict_target_out <= {AW{1'b0}};
    end
    // stall 时保持当前寄存器内容不变，也就是让同一条指令继续停留在 ID 阶段。
    // 这里显式自赋值，是为了更清楚地表达保持行为。
    else if (stall) begin
        pc_out             <= pc_out;
        instr_out          <= instr_out;
        predict_taken_out  <= predict_taken_out;
        predict_target_out <= predict_target_out;
    end
    // 正常流水推进：把 IF 阶段当前取到的指令、PC 以及对应的预测信息
    // 锁存到 IF/ID 寄存器中，供下一拍 ID 阶段使用。
    else begin
        pc_out             <= pc_in;
        instr_out          <= instr_in;
        predict_taken_out  <= predict_taken_in;
        predict_target_out <= predict_target_in;
    end
end
endmodule
