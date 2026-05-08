`timescale 1ns / 1ps
// =============================================================================
// Module   : clint
// Function : Core-Local INTerrupt controller. Handles external, software, and
//            timer interrupts with synchronization and priority arbitration.
// Origin   : Converted from clint.sv (SystemVerilog -> Verilog-2001)
// Changes  : logic->reg/wire, always_ff->always@(posedge), always_comb->always@(*)
// =============================================================================

`include "riscv_defs.vh"

module clint #(
    parameter AW = 32,
    parameter DW = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              jump_en_in,
    input  wire [AW-1:0]     instr_addr_in,
    input  wire [DW-1:0]     instr_in,
    input  wire              external_int_in,
    input  wire              software_int_in,
    input  wire              timer_int_in,
    input  wire              external_int_clear,
    input  wire              software_int_clear,
    input  wire              timer_int_clear,
    // Machine mode CSR
    input  wire [DW-1:0]     mstatus_in,
    input  wire [DW-1:0]     mie_in,
    input  wire [DW-1:0]     mtvec_in,
    input  wire [DW-1:0]     mepc_in,
    output reg  [DW-1:0]     mstatus_out,
    output reg  [DW-1:0]     mcause_out,
    output reg  [DW-1:0]     mepc_out,
    output reg  [DW-1:0]     mip_out,
    output reg  [DW-1:0]     mtval_out,
    // User mode CSR
    input  wire [DW-1:0]     ustatus_in,
    input  wire [DW-1:0]     uie_in,
    input  wire [DW-1:0]     utvec_in,
    input  wire [DW-1:0]     uepc_in,
    output reg  [DW-1:0]     ustatus_out,
    output reg  [DW-1:0]     ucause_out,
    output reg  [DW-1:0]     uepc_out,
    output reg  [DW-1:0]     uip_out,
    output reg  [DW-1:0]     utval_out,
    // Control outputs
    output reg               set_csr_reg,
    output reg               int_en,
    output reg  [AW-1:0]     int_addr
);

wire [6:0] opcode      = instr_in[6:0];
wire       ecall       = (instr_in == `INST_ECALL);
wire       ebreak      = (instr_in == `INST_EBREAK);
wire       mret        = (instr_in == `INST_MRET);
wire       uret        = (instr_in == `INST_URET);

reg        illegal_instr;
reg [DW-1:0] cause;

wire       exception   = illegal_instr | ecall | ebreak;

reg [3:0] external_int_sync;
reg [3:0] software_int_sync;
reg [3:0] timer_int_sync;

reg       external_int_flag;
reg       software_int_flag;
reg       timer_int_flag;

reg       external_int_hold;
reg       software_int_hold;
reg       timer_int_hold;

wire      external_int = (mstatus_in[3] & mip_out[11] & mie_in[11]) |
                         (ustatus_in[0] & uip_out[8]  & uie_in[8]);
wire      software_int = (mstatus_in[3] & mip_out[3]  & mie_in[3]  & (!external_int)) |
                         (ustatus_in[0] & uip_out[0]  & uie_in[0]  & (!external_int));
wire      timer_int    = (mstatus_in[3] & mip_out[7]  & mie_in[7]  & (!external_int) & (!software_int)) |
                         (ustatus_in[0] & uip_out[4]  & uie_in[4]  & (!external_int) & (!software_int));

wire      interrupt_set   = (external_int | software_int | timer_int);

reg       interrupt_set_d0;
reg       interrupt_ready_d0;
reg       jump_en_in_d0;
reg       ret_d0;
reg       ret_d1;

wire      interrupt_ready = (~jump_en_in) & (~jump_en_in_d0) & ((~ret_d0) & (~ret_d1));
wire      interrupt       = (interrupt_ready & (~interrupt_set_d0) & interrupt_set) |
                            (interrupt_set & (~interrupt_ready_d0) & interrupt_ready);

reg       user_domain;
reg       macine_domain;

// Domain tracking
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        user_domain <= 1'b0;
    else if (ustatus_in[0])
        user_domain <= 1'b1;
    else if (uret)
        user_domain <= 1'b0;

always @(posedge clk or negedge rst_n)
    if (!rst_n)
        macine_domain <= 1'b0;
    else if (mstatus_in[3])
        macine_domain <= 1'b1;
    else if (mret)
        macine_domain <= 1'b0;

// Interrupt synchronizers
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
        external_int_sync <= 4'h0;
        software_int_sync <= 4'h0;
        timer_int_sync    <= 4'h0;
    end
    else begin
        external_int_sync <= {external_int_sync[2:0], external_int_in};
        software_int_sync <= {software_int_sync[2:0], software_int_in};
        timer_int_sync    <= {timer_int_sync[2:0],    timer_int_in};
    end

// External interrupt flag
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        external_int_flag <= 1'b0;
    else if ((!external_int_hold) && (!external_int_sync[3]) && external_int_sync[2])
        external_int_flag <= 1'b1;
    else if (external_int_flag && external_int_clear)
        external_int_flag <= 1'b0;

// Software interrupt flag
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        software_int_flag <= 1'b0;
    else if ((!software_int_hold) && (!software_int_sync[3]) && software_int_sync[2])
        software_int_flag <= 1'b1;
    else if (software_int_flag && software_int_clear)
        software_int_flag <= 1'b0;

// Timer interrupt flag
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        timer_int_flag <= 1'b0;
    else if ((!timer_int_hold) && (!timer_int_sync[3]) && timer_int_sync[2])
        timer_int_flag <= 1'b1;
    else if (timer_int_flag && timer_int_clear)
        timer_int_flag <= 1'b0;

// External interrupt hold
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        external_int_hold <= 1'b0;
    else if (external_int_flag && external_int_clear)
        external_int_hold <= 1'b0;
    else if ((!external_int_hold) && (!external_int_sync[3]) && external_int_sync[2])
        external_int_hold <= 1'b1;
    else if (external_int_hold && mret)
        external_int_hold <= 1'b0;
    else if (ret_d0 && external_int_flag)
        external_int_hold <= 1'b1;

// Software interrupt hold
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        software_int_hold <= 1'b0;
    else if (software_int_flag && software_int_clear)
        software_int_hold <= 1'b0;
    else if ((!software_int_hold) && (!software_int_sync[3]) && software_int_sync[2])
        software_int_hold <= 1'b1;
    else if (software_int_hold && mret)
        software_int_hold <= 1'b0;
    else if (ret_d0 && software_int_flag)
        software_int_hold <= 1'b1;

// Timer interrupt hold
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        timer_int_hold <= 1'b0;
    else if (timer_int_flag && timer_int_clear)
        timer_int_hold <= 1'b0;
    else if ((!timer_int_hold) && (!timer_int_sync[3]) && timer_int_sync[2])
        timer_int_hold <= 1'b1;
    else if (timer_int_hold && mret)
        timer_int_hold <= 1'b0;
    else if (ret_d0 && timer_int_flag)
        timer_int_hold <= 1'b1;

// Delay registers
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        interrupt_set_d0 <= 1'b0;
    else
        interrupt_set_d0 <= interrupt_set;

always @(posedge clk or negedge rst_n)
    if (!rst_n)
        interrupt_ready_d0 <= 1'b0;
    else
        interrupt_ready_d0 <= interrupt_ready;

always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
        ret_d0 <= 1'b0;
        ret_d1 <= 1'b0;
    end
    else begin
        ret_d0 <= (mret | uret);
        ret_d1 <= ret_d0;
    end

// Illegal instruction detection
always @(*) begin
    case (opcode)
        `INST_TYPE_I, `INST_TYPE_R_M, `INST_TYPE_B, `INST_TYPE_S, `INST_TYPE_L,
        `INST_JALR, `INST_JAL, `INST_LUI, `INST_LUIPC, `INST_CSR:
            illegal_instr = 1'b0;
        default:
            illegal_instr = 1'b1;
    endcase
end

// Cause generation
always @(*) begin
    if (illegal_instr)
        cause = 32'd2;
    else if (ecall) begin
        if (macine_domain)
            cause = 32'd11;
        else if (user_domain)
            cause = 32'd8;
        else
            cause = 32'd9;
    end
    else if (ebreak)
        cause = 32'd3;
    else if (external_int) begin
        if (macine_domain)
            cause = {1'b1, 31'd11};
        else if (user_domain)
            cause = {1'b1, 31'd8};
        else
            cause = {1'b1, 31'd9};
    end
    else if (software_int) begin
        if (macine_domain)
            cause = {1'b1, 31'd3};
        else if (user_domain)
            cause = {1'b1, 31'd0};
        else
            cause = {1'b1, 31'd1};
    end
    else if (timer_int) begin
        if (macine_domain)
            cause = {1'b1, 31'd7};
        else if (user_domain)
            cause = {1'b1, 31'd4};
        else
            cause = {1'b1, 31'd5};
    end
    else
        cause = 32'd0;
end

// MIP register
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        mip_out <= {DW{1'b0}};
    else if (external_int_clear)
        mip_out <= {mip_out[31:12], 1'b0, mip_out[10:0]};
    else if (software_int_clear)
        mip_out <= {mip_out[31:4], 1'b0, mip_out[2:0]};
    else if (timer_int_clear)
        mip_out <= {mip_out[31:8], 1'b0, mip_out[6:0]};
    else if (external_int_hold)
        mip_out <= {mip_out[31:12], 1'b1, mip_out[10:0]};
    else if (software_int_hold)
        mip_out <= {mip_out[31:4], 1'b1, mip_out[2:0]};
    else if (timer_int_hold)
        mip_out <= {mip_out[31:8], 1'b1, mip_out[6:0]};
    else
        mip_out <= {DW{1'b0}};

// UIP register
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        uip_out <= {DW{1'b0}};
    else if (external_int_clear)
        uip_out <= {uip_out[31:9], 1'b0, uip_out[7:0]};
    else if (software_int_clear)
        uip_out <= {uip_out[31:1], 1'b0};
    else if (timer_int_clear)
        uip_out <= {uip_out[31:5], 1'b0, uip_out[3:0]};
    else if (external_int_hold)
        uip_out <= {uip_out[31:9], 1'b1, uip_out[7:0]};
    else if (software_int_hold)
        uip_out <= {uip_out[31:1], 1'b1};
    else if (timer_int_hold)
        uip_out <= {uip_out[31:5], 1'b1, uip_out[3:0]};
    else
        uip_out <= {DW{1'b0}};

// CSR update on exception/interrupt/return
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
        mstatus_out <= {DW{1'b0}};
        mepc_out    <= {DW{1'b0}};
        mcause_out  <= {DW{1'b0}};
        mtval_out   <= {DW{1'b0}};
        ustatus_out <= {DW{1'b0}};
        uepc_out    <= {DW{1'b0}};
        ucause_out  <= {DW{1'b0}};
        utval_out   <= {DW{1'b0}};
        set_csr_reg <= 1'b0;
    end
    else if (exception) begin
        mstatus_out <= {mstatus_in[31:8], mstatus_in[3], mstatus_in[6:4], 1'b0, mstatus_in[2:0]};
        mepc_out    <= instr_addr_in;
        mcause_out  <= macine_domain ? cause : {DW{1'b0}};
        mtval_out   <= instr_in;
        ustatus_out <= {ustatus_in[31:5], ustatus_in[0], ustatus_in[3:1], 1'b0};
        uepc_out    <= instr_addr_in;
        ucause_out  <= user_domain ? cause : {DW{1'b0}};
        utval_out   <= instr_in;
        set_csr_reg <= 1'b1;
    end
    else if (interrupt) begin
        mstatus_out <= {mstatus_in[31:8], mstatus_in[3], mstatus_in[6:4], 1'b0, mstatus_in[2:0]};
        mepc_out    <= macine_domain ? instr_addr_in : {DW{1'b0}};
        mcause_out  <= macine_domain ? cause : {DW{1'b0}};
        ustatus_out <= {ustatus_in[31:5], ustatus_in[0], ustatus_in[3:1], 1'b0};
        uepc_out    <= user_domain ? instr_addr_in : {DW{1'b0}};
        ucause_out  <= user_domain ? cause : {DW{1'b0}};
        set_csr_reg <= 1'b1;
    end
    else if (mret) begin
        mstatus_out <= {mstatus_in[31:4], mstatus_in[7], mstatus_in[2:0]};
        set_csr_reg <= 1'b1;
    end
    else if (uret) begin
        ustatus_out <= {ustatus_in[31:1], ustatus_in[4]};
        set_csr_reg <= 1'b1;
    end
    else begin
        set_csr_reg <= 1'b0;
    end

// Jump enable delay
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        jump_en_in_d0 <= 1'b0;
    else
        jump_en_in_d0 <= jump_en_in;

// Interrupt address generation
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
        int_en   <= 1'b0;
        int_addr <= {AW{1'b0}};
    end
    else if (exception) begin
        int_en   <= 1'b1;
        int_addr <= {mtvec_in[DW-1:2], 2'b00};
    end
    else if (mret) begin
        int_en   <= 1'b1;
        int_addr <= mepc_in;
    end
    else if (uret) begin
        int_en   <= 1'b1;
        int_addr <= uepc_in;
    end
    else if (interrupt) begin
        int_en <= 1'b1;
        if (macine_domain) begin
            if (external_int)
                int_addr <= mtvec_in[0] ? ({mtvec_in[DW-1:2], 2'b00} + 4*11) : {mtvec_in[DW-1:2], 2'b00};
            else if (software_int)
                int_addr <= mtvec_in[0] ? ({mtvec_in[DW-1:2], 2'b00} + 4*3)  : {mtvec_in[DW-1:2], 2'b00};
            else if (timer_int)
                int_addr <= mtvec_in[0] ? ({mtvec_in[DW-1:2], 2'b00} + 4*7)  : {mtvec_in[DW-1:2], 2'b00};
        end
        else if (user_domain) begin
            if (external_int)
                int_addr <= utvec_in[0] ? ({utvec_in[DW-1:2], 2'b00} + 4*8) : {utvec_in[DW-1:2], 2'b00};
            else if (software_int)
                int_addr <= utvec_in[0] ? ({utvec_in[DW-1:2], 2'b00} + 4*0) : {utvec_in[DW-1:2], 2'b00};
            else if (timer_int)
                int_addr <= utvec_in[0] ? ({utvec_in[DW-1:2], 2'b00} + 4*4) : {utvec_in[DW-1:2], 2'b00};
        end
    end
    else begin
        int_en   <= 1'b0;
        int_addr <= {AW{1'b0}};
    end

endmodule
